module vmail_imap

import net
import time

const default_transport_timeout_ms = 30_000

pub struct PlainTransportOptions {
pub:
	timeout_ms int = default_transport_timeout_ms
}

pub fn test_inbox_unread_count_plain(config ImapConfig, options PlainTransportOptions) !int {
	mut conn := dial_plain_imap(config, options)!
	mut tag_number := 1
	defer {
		logout_plain(mut conn, tag_number) or {}
		conn.close() or {}
	}
	tag_number = login_and_select_plain(mut conn, config, tag_number)!
	search := run_plain_command(mut conn, ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'SEARCH UNSEEN'
	})!
	tag_number++
	return parse_search_ids(search).len
}

pub fn fetch_unseen_messages_plain(config ImapConfig, options PlainTransportOptions) ![]FetchedMessage {
	mut conn := dial_plain_imap(config, options)!
	mut tag_number := 1
	defer {
		logout_plain(mut conn, tag_number) or {}
		conn.close() or {}
	}
	tag_number = login_and_select_plain(mut conn, config, tag_number)!
	search := run_plain_command(mut conn, ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'SEARCH UNSEEN'
	})!
	tag_number++
	ids := parse_search_ids(search)
	if ids.len == 0 {
		return []FetchedMessage{}
	}
	fetch_commands := fetch_rfc822_commands(ids, tag_number)!
	response := run_plain_command(mut conn, fetch_commands[0])!
	return parse_fetch_messages(response)
}

fn dial_plain_imap(config ImapConfig, options PlainTransportOptions) !&net.TcpConn {
	clean := validate_config(config)!
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

fn login_and_select_plain(mut conn net.TcpConn, config ImapConfig, start_tag_number int) !int {
	clean := validate_config(config)!
	mut tag_number := start_tag_number
	for text in [
		'LOGIN ${imap_quote(clean.username)} ${imap_quote(clean.password)}',
		'SELECT ${imap_quote(clean.folder)}',
	] {
		run_plain_command(mut conn, ImapCommand{
			tag:  imap_tag(tag_number)
			text: text
		})!
		tag_number++
	}
	return tag_number
}

fn logout_plain(mut conn net.TcpConn, tag_number int) ! {
	run_plain_command(mut conn, ImapCommand{
		tag:  imap_tag(tag_number)
		text: 'LOGOUT'
	})!
}

fn run_plain_command(mut conn net.TcpConn, command ImapCommand) !string {
	conn.write_string('${command.tag} ${command.text}\r\n')!
	response := read_plain_response(mut conn, command.tag)!
	ensure_tagged_ok(response, command.tag)!
	return response
}

fn read_plain_response(mut conn net.TcpConn, tag string) !string {
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

fn timeout_duration(options PlainTransportOptions) time.Duration {
	timeout_ms := if options.timeout_ms <= 0 {
		default_transport_timeout_ms
	} else {
		options.timeout_ms
	}
	return timeout_ms * time.millisecond
}
