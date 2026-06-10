module vmail_imap

const max_imap_line_bytes = 1024 * 1024

pub interface ImapStream {
mut:
	read(mut []u8) !int
	write_string(string) !int
}

pub struct TransportOptions {
pub:
	timeout_ms int = 30_000
}

pub fn login_and_select(mut stream ImapStream, config ImapConfig, start_tag_number int) !int {
	clean := validate_config(config)!
	mut tag_number := normalized_tag_number(start_tag_number)
	for text in [
		'LOGIN ${imap_quote(clean.username)} ${imap_quote(clean.password)}',
		'SELECT ${imap_quote(clean.folder)}',
	] {
		run_command(mut stream, ImapCommand{
			tag:  imap_tag(tag_number)
			text: text
		})!
		tag_number++
	}
	return tag_number
}

pub fn logout(mut stream ImapStream, tag_number int) ! {
	run_command(mut stream, ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'LOGOUT'
	})!
}

pub fn run_command(mut stream ImapStream, command ImapCommand) !string {
	stream.write_string('${command.tag} ${command.text}\r\n')!
	response := read_response(mut stream, command.tag)!
	ensure_tagged_ok(response, command.tag)!
	return response
}

pub fn read_response(mut stream ImapStream, tag string) !string {
	mut response := ''
	for {
		line := read_line(mut stream)!
		if line == '' {
			return error('imap connection closed before ${tag}')
		}
		response += line
		if literal_size := imap_line_literal_size(line) {
			response += read_literal_bytes(mut stream, literal_size)!
			continue
		}
		if line.trim_space().starts_with('${tag} ') {
			return response
		}
	}
	return response
}

fn imap_line_literal_size(line string) ?int {
	clean := line.trim_right('\r\n')
	if !clean.ends_with('}') {
		return none
	}
	open := clean.last_index('{') or { return none }
	return parse_imap_literal_size(clean[open + 1..clean.len - 1])
}

fn read_literal_bytes(mut stream ImapStream, size int) !string {
	if size < 0 {
		return error('imap literal size must be positive')
	}
	mut out := []u8{cap: size}
	for out.len < size {
		remaining := size - out.len
		chunk_len := if remaining < 4096 { remaining } else { 4096 }
		mut buffer := []u8{len: chunk_len}
		read_count := stream.read(mut buffer)!
		if read_count <= 0 {
			return error('imap connection closed during literal')
		}
		out << buffer[..read_count]
	}
	return out.bytestr()
}

pub fn read_line(mut stream ImapStream) !string {
	mut out := []u8{}
	mut buffer := []u8{len: 1}
	for {
		read_count := stream.read(mut buffer)!
		if read_count <= 0 {
			break
		}
		out << buffer[0]
		if out.len > max_imap_line_bytes {
			return error('imap line exceeded ${max_imap_line_bytes} bytes')
		}
		if buffer[0] == `\n` {
			break
		}
	}
	return out.bytestr()
}

pub fn imap_untagged_ok(line string) bool {
	parts := imap_fields(line)
	return parts.len >= 2 && parts[0] == '*' && parts[1].to_upper() == 'OK'
}

fn ensure_tagged_ok(response string, tag string) ! {
	for line in response.split_into_lines() {
		clean := line.trim_space()
		if clean.starts_with('${tag} ') {
			parts := imap_fields(clean)
			if parts.len >= 2 && parts[1].to_upper() == 'OK' {
				return
			}
			return error(clean)
		}
	}
	return error('missing tagged response ${tag}')
}
