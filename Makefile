TF      = terraform -chdir=terraform

# Ansible est installé dans un environnement Python propre au projet (.venv) :
PYTHON  ?= python3
VENV    = .venv
VENV_OK = $(VENV)/.installed
ANSIBLE = cd ansible && ../$(VENV)/bin/ansible-playbook

.PHONY: check venv init plan up infra swarm demo down ssh password clean-venv

check:          ## Vérifie régions / quotas / tailles autorisées (REGION=francecentral)
	./scripts/check-azure.sh $(REGION)

venv: $(VENV_OK) ## Installe Ansible dans .venv (automatique avant swarm/demo)

# Le fichier témoin .installed dépend de requirements.txt : si on change la
# version d'Ansible, le prochain make réinstalle automatiquement.
$(VENV_OK): requirements.txt
	@$(PYTHON) -c 'import sys; sys.exit(sys.version_info < (3, 10))' || \
		{ echo "Python >= 3.10 requis ($(PYTHON) est trop ancien)"; exit 1; }
	@$(PYTHON) -m venv $(VENV) || \
		{ echo "Impossible de créer le venv : sudo apt install python3-venv"; exit 1; }
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet -r requirements.txt
	@$(VENV)/bin/ansible --version | head -1
	@touch $@

init:
	$(TF) init

plan:
	$(TF) plan

infra:          ## Crée les VM
	$(TF) apply -auto-approve

swarm: $(VENV_OK) ## Installe Docker, monte le Swarm, déploie Portainer
	$(ANSIBLE) site.yml

up: infra swarm ## Tout d'un coup
	@$(TF) output portainer_url

demo: $(VENV_OK) ## Déploie la stack de démo whoami
	$(ANSIBLE) demo.yml

ssh:            ## SSH sur le premier manager
	@eval "$$($(TF) output -raw ssh_manager)"

password:       ## Affiche le mot de passe admin Portainer
	@cat ansible/credentials/portainer_admin; echo

down:           ## Détruit TOUT (arrête la facturation)
	$(TF) destroy -auto-approve
	rm -f ansible/inventory.ini

clean-venv:     ## Supprime l'environnement Python local (recréé au prochain make swarm)
	rm -rf .venv
