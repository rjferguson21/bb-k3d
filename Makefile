# makefile should run deploy.sh

deploy:
	./deploy.sh

hosts:
	@echo "# Generated host entries from values.yaml"
	@echo "# Passthrough hosts:"
	@yq e '.k3d.hostAliases.passthrough.ip + " " + (.k3d.hostAliases.passthrough.hostnames | join(" "))' chart/values.yaml
	@echo "# Public hosts:"
	@yq e '.k3d.hostAliases.public.ip + " " + (.k3d.hostAliases.public.hostnames | join(" "))' chart/values.yaml