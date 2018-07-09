.PHONY: rel

RUN=./tools/silent_exec.sh "$@.log"
XEP_TOOL = tools/xep_tool
EBIN = ebin
DEVNODES = mim1 mim2 mim3 fed1 reg1
REBAR=./rebar3

# Top-level targets aka user interface

all: rel

clean:
	-rm -rf asngen
	-rm -rf _build
	-rm rel/configure.vars.config
	-rm rel/vars.config

# REBAR_CT_EXTRA_ARGS comes from a test runner
ct:
	@(if [ "$(SUITE)" ]; \
		then $(RUN) $(REBAR) ct --dir test --suite $(SUITE) ; \
		else $(RUN) $(REBAR) ct $(REBAR_CT_EXTRA_ARGS); fi)

rel: certs configure.out rel/vars.config
	. ./configure.out && $(REBAR) as prod release

shell: certs etc/ejabberd.cfg
	$(REBAR) shell

# Top-level targets' dependency chain

rock:
	@if [ "$(FILE)" ]; then elvis rock $(FILE);\
	elif [ "$(BRANCH)" ]; then tools/rock_changed.sh $(BRANCH); \
	else tools/rock_changed.sh; fi

rel/vars.config: rel/vars.config.in rel/configure.vars.config
	cat $^ > $@

## Don't allow these files to go out of sync!
configure.out rel/configure.vars.config:
	./tools/configure with-all without-jingle-sip

etc/ejabberd.cfg:
	@mkdir -p $(@D)
	tools/generate_cfg.es etc/ejabberd.cfg rel/files/ejabberd.cfg

devrel: $(DEVNODES)

$(DEVNODES): certs configure.out rel/vars.config
	@echo "building $@"
	(. ./configure.out && \
	DEVNODE=true $(RUN) $(REBAR) as $@ release)

certs: tools/ssl/ca/cacert.pem \
       tools/ssl/fake_cert.pem \
       tools/ssl/fake_key.pem \
       tools/ssl/fake_pubkey.pem \
       tools/ssl/fake_server.pem \
       tools/ssl/fake_dh_server.pem

tools/ssl/ca/cacert.pem \
tools/ssl/fake_cert.pem \
tools/ssl/fake_key.pem \
tools/ssl/fake_pubkey.pem \
tools/ssl/fake_server.pem \
tools/ssl/fake_dh_server.pem:
	cd tools/ssl && $(MAKE)

xeplist: escript
	escript $(XEP_TOOL)/xep_tool.escript markdown $(EBIN)

install: configure.out rel
	@. ./configure.out && tools/install

cover_report: /tmp/mongoose_combined.coverdata
	$(RUN) erl -noshell -pa _build/default/lib/*/ebin \
			-eval 'ecoveralls:travis_ci("$?"), init:stop()'
