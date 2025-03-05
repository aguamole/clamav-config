#!/bin/bash

set -e -u

## Programa para configurar o CLAMAV no Kubuntu.
#=============================================================================#
## Variaveis
SEGUNDOS='5'

script_de_start_do_clamonacc_home_separada='#!/usr/bin/env bash

# Script para inicializar o clamonacc com parametros em home separada.

SEGUNDOS="1"   # Tempo em segundos

while true; do
    # Verifica se o dispositivo está montado
    if [[ $(mount | grep "/dev/sd?? on /home") ]]
    then
        echo "Dispositivo está montado. Executando o comando..."
        /usr/sbin/clamonacc -F --wait --config-file=/etc/clamav/clamd.conf --log=/var/log/clamav/clamonacc.log
    else
        echo "Dispositivo não está montado. Aguardando..."
    fi

    # Aguarda antes de tentar novamente
    sleep "${SEGUNDOS}"  # Espera por segundos antes de verificar novamente
done'

script_de_start_do_clamonacc='#!/bin/bash

# Script para inicializar o clamonacc com parametros.

SEGUNDOS="1"

while true
do
    /usr/sbin/clamonacc -F --wait --config-file=/etc/clamav/clamd.conf --log=/var/log/clamav/clamonacc.log || continue
    sleeep "${SEGUNDOS}"
done'

script_de_clamonacc_notify='#!/usr/bin/env bash

# Programa para notificar quando o log clamonacc.log foi alterado
# emitindo um aleta de infeção por malware.

# Configuração
time_segundo="2"

mudanca_atual=$(tail -n 1 /var/log/clamav/clamonacc.log)
ultima_mudanca="${mudanca_atual}"

while true; do
    sleep "${time_segundo}"

    mudanca_atual=$(tail -n 1 /var/log/clamav/clamonacc.log)

   [[ "${ultima_mudanca}" != "${mudanca_atual}" ]] &&

    if tail -n 1 /var/log/clamav/clamonacc.log | grep "FOUND"; then
        zenity --info --title="Arquivo modificado" --text="O arquivo clamonacc.log foi modificado. \nÚltimas 6 linhas do arquivo:\n$(tail -6 /var/log/clamav/clamonacc.log)" --ok-label="Abrir log" --extra-button="Cancelar"
        if [ $? -eq 0 ]; then
            kate /var/log/clamav/clamonacc.log
        fi
    ultima_mudanca="${mudanca_atual}"
    fi
done'

script_de_clamonacc_no_systemd='[Unit]
Description=Serviço para iniciar o Clamd On Access.
Requires=clamav-daemon.service
After=clamav-daemon.service syslog.target network.target

[Service]
Type=simple
User=root
ExecStart=/sbin/clamonacc_bash.sh

[Install]
WantedBy=multi-user.target
'

configuracao_systemd='# Minhas configurações
# OnAccessMountPath "/"
OnAccessExcludeUname root
OnAccessMaxThreads null
OnAccessPrevention yes
OnAccessIncludePath "/home/"'
#=============================================================================#
## Funções

#=============================================================================#
## Main
read -r -p "Sua home é separada? (y/n) " yes_home_separada
[[ "${yes_home_separada,,}" == 'y' ]] && read -r -p 'Qual é o dispositivo "/dev/sd??"? ' dispositivo_home

if [[ "$(cat /boot/config-$(uname -r) | grep FANOTIFY)" == 'CONFIG_FANOTIFY_ACCESS_PERMISSIONS is not set' ]]
then
    echo "Habilite o FANOTIFY na compilação do kernel Linux."
    exit 1
fi

if [[ "$(command -v curl)" ]]
then
    echo "Curl instalado"
else
    apt-get install curl -y
fi

echo "Instalando CLAMAV"
apt-get install clamav-daemon clamav-base clamav-freshclam clamav-milter clamav-docs clamav clamdscan -y

# Fazendo copia de segurança de clamd.conf
if [[  -f "/etc/clamav/clamd.conf" ]]
then
    cp "/etc/clamav/clamd.conf" "/etc/clamav/clamd.conf.exemple"
else
    echo 'O arquivo /etc/clamav.conf não foi encontrado.'
    exit 2
fi

# Finalizar clamd e editar clamad.conf com sed
killall -15 clamd ||
sed -i 's/LocalSocketMode 666/LocalSocketMode 660/' "/etc/clamav/clamd.conf"
echo "${configuracao_systemd}" | sed "4 s/null/$(nproc)/" >>"/etc/clamav/clamd.conf"
sed -i '10 s/User clamav/User root/' "/etc/clamav/clamd.conf"

# Inicia serviços
systemctl enable clamav-freshclam.service
sleep "${SEGUNDOS}"
systemctl start clamav-freshclam.service
sleep "${SEGUNDOS}"
systemctl enable clamav-daemon.service
sleep "${SEGUNDOS}"
systemctl start clamav-daemon.service
sleep "${SEGUNDOS}"

# Verifica se o serviço clamav daemon foi iniciado
if [[ $(systemctl status clamav-daemon.service | grep 'Active: ' | sed 's/.*(//;s/).*//') != 'running' ]]
then
    clear
    echo "Falha ao iniciar serviço clamav-daemon!"
    echo "Isso pode ser normal, pode demorar um pouco iniciar o serviço clamav-daemon!"
    echo "Tente novamente mais tarde!"
    exit '1'
fi

# Se for pasta pessoal separada
[[ "${yes_home_separada,,}" == 'y' ]] && echo "${script_de_start_do_clamonacc_home_separada}" | sed "9 s./dev/sd??.${dispositivo_home}." >"/sbin/clamonacc_bash.sh" ||
    echo "${script_de_start_do_clamonacc}" >"/sbin/clamonacc_bash.sh"

# Configura o clamav
chmod +x "/sbin/clamonacc_bash.sh"
echo "${script_de_clamonacc_notify}" >"/bin/clamonacc_notify.sh"
chmod +x "/bin/clamonacc_notify.sh"
>"/var/log/clamav/clamonacc.log"
chmod +r "/var/log/clamav/clamonacc.log"

echo "${script_de_clamonacc_no_systemd}" >"/etc/systemd/system/clamonacc.service"

# Inicia o serviço de real time protection
systemctl enable clamonacc.service
sleep "${SEGUNDOS}"
systemctl start clamonacc.service
clear

echo "Configuração concluida, realize o teste com o Eicar test imediatamente."
