module imap_plain

import net
import time
import vmail_imap

const default_transport_timeout_ms = 30_000

pub struct TransportOptions {
pub:
	timeout_ms int = default_transport_timeout_ms
}

pub fn test_inbox_unread_count(config vmail_imap.ImapConfig, options TransportOptions) !int {
	mut conn := dial(config, options)!
	mut tag_number := 1
	defer {
		logout(mut conn, tag_number) or {}
		conn.close() or {}
	}
	tag_number = login_and_select(mut conn, config, tag_number)!
	search := run_command(mut conn, vmail_imap.ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'SEARCH UNSEEN'
	})!
	return vmail_imap.parse_search_ids(search).len
}

pub fn fetch_unseen_messages(config vmail_imap.ImapConfig, options TransportOptions) ![]vmail_imap.FetchedMessage {
	mut conn := dial(config, options)!
	mut tag_number := 1
	defer {
		logout(mut conn, tag_number) or {}
		conn.close() or {}
	}
	tag_number = login_and_select(mut conn, config, tag_number)!
	search := run_command(mut conn, vmail_imap.ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'SEARCH UNSEEN'
	})!
	tag_number++
	ids := vmail_imap.parse_search_ids(search)
	if ids.len == 0 {
		return []vmail_imap.FetchedMessage{}
	}
	fetch_commands := vmail_imap.fetch_rfc822_commands(ids, tag_number)!
	response := run_command(mut conn, fetch_commands[0])!
	return vmail_imap.parse_fetch_messages(response)
}

pub fn delete_messages_by_uid(config vmail_imap.ImapConfig, uids []string, options TransportOptions) ! {
	delete_commands := vmail_imap.delete_uid_commands(uids, 1)!
	if delete_commands.len == 0 {
		return
	}
	mut conn := dial(config, options)!
	mut tag_number := 1
	defer {
		logout(mut conn, tag_number) or {}
		conn.close() or {}
	}
	tag_number = login_and_select(mut conn, config, tag_number)!
	for command in vmail_imap.delete_uid_commands(uids, tag_number)! {
		run_command(mut conn, command)!
		tag_number++
	}
}

fn dial(config vmail_imap.ImapConfig, options TransportOptions) !&net.TcpConn {
	clean := vmail_imap.validate_config(config)!
	if clean.ssl || clean.starttls {
		return error('plain IMAP transport requires ssl=false and starttls=false')
	}
	mut conn := net.dial_tcp('${clean.host}:${clean.port}')!
	timeout := timeout_duration(options)
	conn.set_read_timeout(timeout)
	conn.set_write_timeout(timeout)
	greeting := conn.read_line()
	if !imap_untagged_ok(greeting) {
		conn.close() or {}
		return error('imap greeting was not OK')
	}
	return conn
}

fn login_and_select(mut conn net.TcpConn, config vmail_imap.ImapConfig, start_tag_number int) !int {
	clean := vmail_imap.validate_config(config)!
	mut tag_number := start_tag_number
	for text in [
		'LOGIN ${vmail_imap.imap_quote(clean.username)} ${vmail_imap.imap_quote(clean.password)}',
		'SELECT ${vmail_imap.imap_quote(clean.folder)}',
	] {
		run_command(mut conn, vmail_imap.ImapCommand{
			tag:  imap_tag(tag_number)
			text: text
		})!
		tag_number++
	}
	return tag_number
}

fn logout(mut conn net.TcpConn, tag_number int) ! {
	run_command(mut conn, vmail_imap.ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'LOGOUT'
	})!
}

fn run_command(mut conn net.TcpConn, command vmail_imap.ImapCommand) !string {
	conn.write_string('${command.tag} ${command.text}\r\n')!
	response := read_response(mut conn, command.tag)!
	ensure_tagged_ok(response, command.tag)!
	return response
}

fn read_response(mut conn net.TcpConn, tag string) !string {
	mut response := ''
	for {
		line := conn.read_line()
		if line == '' {
			return error('imap connection closed before ${tag}')
		}
		response += line
		if line.trim_space().starts_with('${tag} ') {
			return response
		}
	}
	return response
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

fn imap_untagged_ok(line string) bool {
	parts := imap_fields(line)
	return parts.len >= 2 && parts[0] == '*' && parts[1].to_upper() == 'OK'
}

fn imap_fields(value string) []string {
	mut fields := []string{}
	for part in value.trim_space().split(' ') {
		clean := part.trim_space()
		if clean != '' {
			fields << clean
		}
	}
	return fields
}

fn imap_tag(number int) string {
	return 'A${number:03}'
}

fn timeout_duration(options TransportOptions) time.Duration {
	timeout_ms := if options.timeout_ms <= 0 {
		default_transport_timeout_ms
	} else {
		options.timeout_ms
	}
	return timeout_ms * time.millisecond
}
