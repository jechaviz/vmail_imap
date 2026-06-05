module imap_tls

import net
import net.mbedtls
import os
import vmail_imap

const tls_cert_path = 'C:/git/v/examples/ssl_server/cert/server.crt'
const tls_key_path = 'C:/git/v/examples/ssl_server/cert/server.key'

fn test_tls_transport_counts_fetches_and_deletes_unseen_messages() {
	if !os.exists(tls_cert_path) || !os.exists(tls_key_path) {
		eprintln('skipping tls imap test because V ssl_server certs are missing')
		return
	}
	port_channel := chan int{cap: 1}
	spawn fake_tls_imap_server(port_channel)
	port := <-port_channel
	assert port > 0
	config := vmail_imap.ImapConfig{
		host:     '127.0.0.1'
		port:     port
		username: 'inbox@example.test'
		password: 'secret'
		folder:   'INBOX'
		ssl:      true
	}
	options := vmail_imap.TransportOptions{
		timeout_ms: 5_000
	}
	assert test_inbox_unread_count(config, options)! == 2
	messages := fetch_unseen_messages(config, options)!
	assert messages.len == 2
	assert messages[0].uid == '21'
	assert messages[0].raw.contains('Subject: TLS One')
	assert messages[1].uid == '22'
	assert messages[1].raw.contains('Subject: TLS Two')
	delete_messages_by_uid(config, ['21', '22'], options)!
}

fn fake_tls_imap_server(port_channel chan int) {
	mut port_listener := net.listen_tcp(.ip, '127.0.0.1:0') or {
		port_channel <- 0
		return
	}
	port := port_listener.addr() or {
		port_channel <- 0
		return
	}.port() or {
		port_channel <- 0
		return
	}
	port_listener.close() or {}
	mut listener := mbedtls.new_ssl_listener('127.0.0.1:${port}', mbedtls.SSLConnectConfig{
		cert:     tls_cert_path
		cert_key: tls_key_path
		validate: false
	}) or {
		port_channel <- 0
		return
	}
	port_channel <- port
	for _ in 0 .. 3 {
		mut conn := listener.accept() or { break }
		handle_fake_tls_imap_connection(mut conn)
		conn.shutdown() or {}
	}
	listener.shutdown() or {}
}

fn handle_fake_tls_imap_connection(mut conn mbedtls.SSLConn) {
	conn.write_string('* OK fake tls imap ready\r\n') or { return }
	raw_one := 'Subject: TLS One\r\n\r\nBody one'
	raw_two := 'Subject: TLS Two\r\n\r\nBody two'
	for {
		line := vmail_imap.read_line(mut conn) or { return }
		if line == '' {
			return
		}
		tag := line.trim_space().split(' ')[0]
		upper := line.to_upper()
		if upper.contains('LOGIN') {
			conn.write_string('${tag} OK LOGIN completed\r\n') or { return }
		} else if upper.contains('SELECT') {
			conn.write_string('* FLAGS (\\Seen)\r\n${tag} OK SELECT completed\r\n') or { return }
		} else if upper.contains('SEARCH') {
			conn.write_string('* SEARCH 1 2\r\n${tag} OK SEARCH completed\r\n') or { return }
		} else if upper.contains('FETCH') {
			response :=
				'* 1 FETCH (UID 21 RFC822 {${raw_one.len}}\r\n${raw_one})\r\n' + '* 2 FETCH (UID 22 RFC822 {${raw_two.len}}\r\n${raw_two})\r\n' + '${tag} OK FETCH completed\r\n'
			conn.write_string(response) or { return }
		} else if upper.contains('UID STORE') {
			conn.write_string('${tag} OK STORE completed\r\n') or { return }
		} else if upper.contains('EXPUNGE') {
			conn.write_string('* 1 EXPUNGE\r\n${tag} OK EXPUNGE completed\r\n') or { return }
		} else if upper.contains('LOGOUT') {
			conn.write_string('* BYE logging out\r\n${tag} OK LOGOUT completed\r\n') or { return }
			return
		} else {
			conn.write_string('${tag} BAD unsupported\r\n') or { return }
		}
	}
}
