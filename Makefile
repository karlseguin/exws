F=
PIDFILE=/tmp/ws.pid

.PHONY: t
t:
	mix test ${F}

.PHONY: s
s:
	env MIX_ENV=ab mix run -e 'ExWs.Server.start_for_tests()'

.PHONY: ab
ab:
	env MIX_ENV=ab mix compile
	env MIX_ENV=ab mix run -e 'ExWs.Server.start_for_tests()' & echo $$! > $(PIDFILE)
	sleep 1 # give chance for socket to listen

	docker run --rm \
		--net="host" \
		-v "$(PWD)/autobahn/config:/config" \
		-v "$(PWD)/autobahn/reports:/reports" \
		--name fuzzingclient \
		--platform linux/amd64 \
		crossbario/autobahn-testsuite \
		/opt/pypy/bin/wstest --mode fuzzingclient --spec /config/config.json;
	kill $$(cat $(PIDFILE)) || true;
	rm $(PIDFILE)
	@if grep FAILED autobahn/reports/index.json*; \
	then exit 1; \
	else exit 0; \
	fi

