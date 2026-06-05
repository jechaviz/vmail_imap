module imap_plain

import net
import vmail_imap

fn test_plain_transport_counts_and_fetches_unseen_messages() {
	port_channel := chan int{cap: 1}
	spawn fake_imap_server(port_channel)
	port := <-port_channel
	assert port > 0
	config := vmail_imap.ImapConfig{
		host:     '127.0.0.1'
		port:     port
		username: 'inbox@example.test'
		password: 'secret'
		folder:   'INBOX'
	}
	options := TransportOptions{
		timeout_ms: 5_000
	}
	assert test_inbox_unread_count(config, options)! == 2
	messages := fetch_unseen_messages(config, options)!
	assert messages.len == 2
	assert messages[0].uid == '11'
	assert messages[0].raw.contains('Subject: One')
	assert messages[1].uid == '12'
	assert messages[1].raw.contains('Subject: Two')
}

fn fake_imap_server(port_channel chan int) {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or {
		port_channel <- 0
		return
	}
	addr := listener.addr() or {
		port_channel <- 0
		return
	}
	port_channel <- addr.str().all_after_last(':').int()
	for _ in 0 .. 2 {
		mut conn := listener.accept() or { return }
		handle_fake_imap_connection(mut conn)
		conn.close() or {}
	}
	listener.close() or {}
}

fn handle_fake_imap_connection(mut conn net.TcpConn) {
	conn.write_string('* OK fake imap ready\r\n') or { return }
	raw_one := 'Subject: One\r\n\r\nBody one'
	raw_two := 'Subject: Two\r\n\r\nBody two'
	for {
		line := conn.read_line()
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
				'* 1 FETCH (UID 11 RFC822 {${raw_one.len}}\r\n${raw_one})\r\n' + '* 2 FETCH (UID 12 RFC822 {${raw_two.len}}\r\n${raw_two})\r\n' + '${tag} OK FETCH completed\r\n'
			conn.write_string(response) or { return }
		} else if upper.contains('LOGOUT') {
			conn.write_string('* BYE logging out\r\n${tag} OK LOGOUT completed\r\n') or { return }
			return
		} else {
			conn.write_string('${tag} BAD unsupported\r\n') or { return }
		}
	}
}
