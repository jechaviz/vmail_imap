module imap_plain

import net
import time
import vmail_imap

const default_transport_timeout_ms = 30_000

pub fn test_inbox_unread_count(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !int {
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

pub fn fetch_unseen_messages(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) ![]vmail_imap.FetchedMessage {
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

pub fn delete_messages_by_uid(config vmail_imap.ImapConfig, uids []string, options vmail_imap.TransportOptions) ! {
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

fn dial(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !&net.TcpConn {
	clean := vmail_imap.validate_config(config)!
	if clean.ssl || clean.starttls {
		return error('plain IMAP transport requires ssl=false and starttls=false')
	}
	mut conn := net.dial_tcp('${clean.host}:${clean.port}')!
	timeout := timeout_duration(options)
	conn.set_read_timeout(timeout)
	conn.set_write_timeout(timeout)
	greeting := vmail_imap.read_line(mut conn)!
	if !vmail_imap.imap_untagged_ok(greeting) {
		conn.close() or {}
		return error('imap greeting was not OK')
	}
	return conn
}

fn login_and_select(mut conn net.TcpConn, config vmail_imap.ImapConfig, start_tag_number int) !int {
	return vmail_imap.login_and_select(mut conn, config, start_tag_number)!
}

fn logout(mut conn net.TcpConn, tag_number int) ! {
	vmail_imap.logout(mut conn, tag_number)!
}

fn run_command(mut conn net.TcpConn, command vmail_imap.ImapCommand) !string {
	return vmail_imap.run_command(mut conn, command)!
}

fn imap_tag(number int) string {
	return vmail_imap.imap_tag(number)
}

fn timeout_duration(options vmail_imap.TransportOptions) time.Duration {
	timeout_ms := if options.timeout_ms <= 0 {
		default_transport_timeout_ms
	} else {
		options.timeout_ms
	}
	return timeout_ms * time.millisecond
}
