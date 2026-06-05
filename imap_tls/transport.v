module imap_tls

import net
import net.ssl
import time
import vmail_imap

const default_transport_timeout_ms = 30_000

struct SecureConn {
mut:
	tls       &ssl.SSLConn = unsafe { nil }
	tcp       &net.TcpConn = unsafe { nil }
	close_tcp bool
}

struct Session {
mut:
	conn       SecureConn
	tag_number int
}

pub fn test_inbox_unread_count(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !int {
	mut session := open_session(config, options)!
	defer {
		close_session(mut session)
	}
	search := vmail_imap.run_command(mut session.conn, vmail_imap.ImapCommand{
		tag:  vmail_imap.imap_tag(session.tag_number)
		text: 'SEARCH UNSEEN'
	})!
	return vmail_imap.parse_search_ids(search).len
}

pub fn fetch_unseen_messages(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) ![]vmail_imap.FetchedMessage {
	mut session := open_session(config, options)!
	defer {
		close_session(mut session)
	}
	search := vmail_imap.run_command(mut session.conn, vmail_imap.ImapCommand{
		tag:  vmail_imap.imap_tag(session.tag_number)
		text: 'SEARCH UNSEEN'
	})!
	session.tag_number++
	ids := vmail_imap.parse_search_ids(search)
	if ids.len == 0 {
		return []vmail_imap.FetchedMessage{}
	}
	fetch_commands := vmail_imap.fetch_rfc822_commands(ids, session.tag_number)!
	response := vmail_imap.run_command(mut session.conn, fetch_commands[0])!
	return vmail_imap.parse_fetch_messages(response)
}

pub fn delete_messages_by_uid(config vmail_imap.ImapConfig, uids []string, options vmail_imap.TransportOptions) ! {
	delete_commands := vmail_imap.delete_uid_commands(uids, 1)!
	if delete_commands.len == 0 {
		return
	}
	mut session := open_session(config, options)!
	defer {
		close_session(mut session)
	}
	for command in vmail_imap.delete_uid_commands(uids, session.tag_number)! {
		vmail_imap.run_command(mut session.conn, command)!
		session.tag_number++
	}
}

fn open_session(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !Session {
	mut session := dial(config, options)!
	session.tag_number = vmail_imap.login_and_select(mut session.conn, config, session.tag_number)!
	return session
}

fn close_session(mut session Session) {
	vmail_imap.logout(mut session.conn, session.tag_number) or {}
	session.conn.close() or {}
}

fn dial(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !Session {
	clean := vmail_imap.validate_config(config)!
	if clean.ssl {
		return dial_ssl(clean, options)!
	}
	if clean.starttls {
		return dial_starttls(clean, options)!
	}
	return error('secure IMAP transport requires ssl=true or starttls=true')
}

fn dial_ssl(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !Session {
	timeout := timeout_duration(options)
	mut tls := ssl.new_ssl_conn(ssl.SSLConnectConfig{
		validate: false
	})!
	tls.set_read_timeout(timeout)
	tls.dial(config.host, config.port) or {
		tls.shutdown() or {}
		return err
	}
	mut conn := SecureConn{
		tls: tls
	}
	greeting := vmail_imap.read_line(mut conn)!
	if !vmail_imap.imap_untagged_ok(greeting) {
		conn.close() or {}
		return error('imap greeting was not OK')
	}
	return Session{
		conn:       conn
		tag_number: 1
	}
}

fn dial_starttls(config vmail_imap.ImapConfig, options vmail_imap.TransportOptions) !Session {
	timeout := timeout_duration(options)
	mut tcp := net.dial_tcp('${config.host}:${config.port}')!
	tcp.set_read_timeout(timeout)
	tcp.set_write_timeout(timeout)
	greeting := vmail_imap.read_line(mut tcp)!
	if !vmail_imap.imap_untagged_ok(greeting) {
		tcp.close() or {}
		return error('imap greeting was not OK')
	}
	vmail_imap.run_command(mut tcp, vmail_imap.ImapCommand{
		tag:  vmail_imap.imap_tag(1)
		text: 'STARTTLS'
	})!
	mut tls := ssl.new_ssl_conn(ssl.SSLConnectConfig{
		validate: false
	})!
	tls.connect(mut tcp, config.host) or {
		tls.shutdown() or {}
		tcp.close() or {}
		return err
	}
	tls.set_read_timeout(timeout)
	return Session{
		conn:       SecureConn{
			tls:       tls
			tcp:       tcp
			close_tcp: true
		}
		tag_number: 2
	}
}

fn (mut conn SecureConn) read(mut buffer []u8) !int {
	return conn.tls.read(mut buffer)
}

fn (mut conn SecureConn) write_string(value string) !int {
	return conn.tls.write_string(value)
}

fn (mut conn SecureConn) close() ! {
	conn.tls.shutdown() or {}
	if conn.close_tcp {
		conn.tcp.close()!
	}
}

fn timeout_duration(options vmail_imap.TransportOptions) time.Duration {
	timeout_ms := if options.timeout_ms <= 0 {
		default_transport_timeout_ms
	} else {
		options.timeout_ms
	}
	return timeout_ms * time.millisecond
}
