#!/usr/bin/env bash
# Vérifie ce que l'abonnement étudiant autorise AVANT de lancer Terraform.
# Usage : ./scripts/check-azure.sh [region]      (défaut : francecentral)
set -euo pipefail

LOCATION="${1:-francecentral}"

if ! az account show >/dev/null 2>&1; then
  echo "Non connecté : lancer d'abord 'az login'" >&2
  exit 1
fi

SUB_ID=$(az account show --query id -o tsv | tr -d '\r')
SUB_NAME=$(az account show --query name -o tsv | tr -d '\r')
echo "Abonnement : ${SUB_NAME} (${SUB_ID})"
echo

echo "== 1. Restrictions de région imposées par les policies =="
POLICIES=$(az policy assignment list --disable-scope-strict-match \
  --query "[?contains(displayName || '', 'region') || contains(displayName || '', 'location')].[policyDefinitionId, join(', ', parameters.listOfAllowedLocations.value || \`[]\`)]" \
  -o tsv | tr -d '\r') || POLICIES=""

if [ -z "${POLICIES}" ]; then
  echo "(aucune policy de région trouvée : vérifier dans le portail Azure, rubrique Policy > Affectations)"
else
  while IFS=$'\t' read -r def_id regions; do
    rule=$(az policy definition show --name "${def_id##*/}" --query displayName -o tsv 2>/dev/null | tr -d '\r' || echo "${def_id##*/}")
    echo "- ${rule}"
    if [ -n "${regions}" ]; then
      echo "    régions autorisées : ${regions}"
    fi
  done <<< "${POLICIES}"
fi
echo

echo "== 2. Quota vCPU dans ${LOCATION} =="
az vm list-usage --location "${LOCATION}" \
  --query "[?name.value=='cores' || contains(name.value, 'BS')].{Quota:localName, Utilise:currentValue, Limite:limit}" \
  -o table
echo

echo "== 3. Petites tailles de VM réellement disponibles pour cet abonnement dans ${LOCATION} =="
echo "   (une taille absente de la liste = non autorisée ou sans capacité)"
az vm list-skus --location "${LOCATION}" --resource-type virtualMachines --size Standard_B \
  --query "[?contains(['Standard_B1s','Standard_B1ms','Standard_B2s','Standard_B2ats_v2','Standard_B2als_v2','Standard_B2ts_v2'], name)].{Taille:name, vCPU:capabilities[?name=='vCPUs'].value | [0], RAM_Go:capabilities[?name=='MemoryGB'].value | [0], Restrictions:join(',', restrictions[].reasonCode)}" \
  -o table
echo
echo "Rappel : vm_size x nombre de VM doit rester <= quota 'Total Regional vCPUs'."
