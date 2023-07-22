.PHONY: check docs test

check:
	find src -type f -name '*.mo' -print0 | xargs -0 $(shell vessel bin)/moc $(shell vessel sources) --check

all: check-strict docs test

check-strict:
	find src -type f -name '*.mo' -print0 | xargs -0 $(shell vessel bin)/moc $(shell vessel sources) -Werror --check
docs:
	$(shell vessel bin)/mo-doc
test:
	for file in test/*.test.mo; do $(shell vessel bin)/moc $(shell vessel sources 2>/dev/null) -r "$$file"; done