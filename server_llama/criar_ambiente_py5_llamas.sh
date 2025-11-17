#!/bin/bash
# Script de configuração do ambiente Python para Flask + Ollama ESP32 server

set -euo pipefail

MODEL_BASE="$HOME/Athena/_VOZES"

VENV_DIR="$HOME/esp32_ollama_virtual/venv"
REQUIRED_APT_PACKAGES=(python3 python3-venv python3-pip curl wget)

# Lista de modelos disponíveis
declare -A OLLAMA_MODELS=(
    ["gemma3:1b"]="Gemma 3 1B - 815MB"
    ["gemma3"]="Gemma 3 4B - 3.3GB"
    ["gemma3:12b"]="Gemma 3 12B - 8.1GB"
    ["gemma3:27b"]="Gemma 3 27B - 17GB"
    ["qwq"]="QwQ 32B - 20GB"
    ["deepseek-r1"]="DeepSeek-R1 7B - 4.7GB"
    ["deepseek-r1:671b"]="DeepSeek-R1 671B - 404GB"
    ["llama4:scout"]="Llama 4 109B - 67GB"
    ["llama4:maverick"]="Llama 4 400B - 245GB"
    ["llama3.3"]="Llama 3.3 70B - 43GB"
    ["llama3.2"]="Llama 3.2 3B - 2.0GB"
    ["llama3.2:1b"]="Llama 3.2 1B - 1.3GB"
    ["llama3.2-vision"]="Llama 3.2 Vision 11B - 7.9GB"
    ["llama3.2-vision:90b"]="Llama 3.2 Vision 90B - 55GB"
    ["llama3.1"]="Llama 3.1 8B - 4.7GB"
    ["llama3.1:405b"]="Llama 3.1 405B - 231GB"
    ["phi4"]="Phi 4 14B - 9.1GB"
    ["phi4-mini"]="Phi 4 Mini 3.8B - 2.5GB"
    ["mistral"]="Mistral 7B - 4.1GB"
    ["moondream"]="Moondream 2 1.4B - 829MB"
    ["neural-chat"]="Neural Chat 7B - 4.1GB"
    ["starling-lm"]="Starling 7B - 4.1GB"
    ["codellama"]="Code Llama 7B - 3.8GB"
    ["llama2-uncensored"]="Llama 2 Uncensored 7B - 3.8GB"
    ["llava"]="LLaVA 7B - 4.5GB"
    ["granite3.3"]="Granite-3.3 8B - 4.9GB"
)

# Funções utilitárias
check_internet() {
    if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1 && curl -sSf --connect-timeout 5 https://www.google.com >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

confirm() {
    # $1 = mensagem; responde true se sim
    read -r -p "$1 [y/N]: " ans
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0;;
        *) return 1;;
    esac
}

select_model() {
    echo ""
    echo "=== Modelos Ollama Disponíveis ==="
    echo "Selecione um modelo para instalar:"
    echo ""
    
    local i=1
    local model_names=()
    
    # Criar arrays para ordenação
    for model in "${!OLLAMA_MODELS[@]}"; do
        model_names[$i]="$model"
        echo "$i. ${OLLAMA_MODELS[$model]}"
        ((i++))
    done
    
    echo ""
    read -r -p "Digite o número do modelo (ou Enter para pular): " choice
    
    if [[ -z "$choice" ]]; then
        echo "Nenhum modelo selecionado."
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#model_names[@]}" ]]; then
        SELECTED_MODEL="${model_names[$choice]}"
        echo "Modelo selecionado: $SELECTED_MODEL - ${OLLAMA_MODELS[$SELECTED_MODEL]}"
        return 0
    else
        echo "Seleção inválida."
        return 1
    fi
}

# Início do script
echo "=== Configuração do ambiente Flask + Ollama ESP32 Server ==="

# Verifica internet antes de operações que requerem rede
if check_internet; then
    HAVE_INTERNET=1
else
    HAVE_INTERNET=0
    echo "Aviso: sem conexão com internet detectada. Operações de download/apt serão puladas."
fi

# Se internet existente, perguntar sobre instalação apt
if [ "$HAVE_INTERNET" -eq 1 ]; then
    if confirm "Deseja atualizar a lista de pacotes e instalar dependências do sistema via apt (requer sudo)?"; then
        echo "Executando apt update/install (pode pedir sua senha sudo)..."
        sudo apt-get update
        sudo apt-get install -y "${REQUIRED_APT_PACKAGES[@]}"
    else
        echo "Pulando instalação via apt conforme solicitado."
    fi
else
    echo "Sem internet: pule apt/install de dependências. Instale manualmente se necessário."
fi

# Instalar Ollama
echo ""
echo "=== Instalação do Ollama ==="
if command -v ollama >/dev/null 2>&1; then
    echo "Ollama já está instalado."
    ollama --version
else
    if [ "$HAVE_INTERNET" -eq 1 ]; then
        if confirm "Deseja instalar Ollama (requer sudo)?"; then
            echo "Instalando Ollama..."
            curl -fsSL https://ollama.com/install.sh | sh
        else
            echo "Pulando instalação do Ollama conforme solicitado."
            echo "Você pode instalá-lo manualmente com: curl -fsSL https://ollama.com/install.sh | sh"
        fi
    else
        echo "Sem internet: não é possível instalar Ollama agora."
    fi
fi

# Iniciar o serviço `ollama serve` em background (antes de puxar qualquer modelo)
OLLAMA_LOG="$HOME/.ollama/ollama_server.log"
OLLAMA_PIDFILE="$HOME/.ollama_server.pid"

start_ollama_server() {
    if ! command -v ollama >/dev/null 2>&1; then
        echo "Ollama não encontrado; pulando start do servidor."
        return 2
    fi

    if [ -f "$OLLAMA_PIDFILE" ] && kill -0 "$(cat "$OLLAMA_PIDFILE")" >/dev/null 2>&1; then
        echo "Ollama server já está rodando (PID $(cat "$OLLAMA_PIDFILE"))."
        return 0
    fi

    echo "Iniciando 'ollama serve' em background (log: $OLLAMA_LOG) ..."
    mkdir -p "$(dirname "$OLLAMA_LOG")"
    nohup ollama serve >"$OLLAMA_LOG" 2>&1 &
    echo $! >"$OLLAMA_PIDFILE"

    # Espera o servidor ficar disponível (timeout em segundos)
    timeout_sec=60
    waited=0
    sleep 0.5
    while [ $waited -lt $timeout_sec ]; do
        if command -v curl >/dev/null 2>&1; then
            if curl -sS --fail http://127.0.0.1:11434/v1/models >/dev/null 2>&1; then
                echo "Ollama server pronto."
                return 0
            fi
        fi
        if ollama status >/dev/null 2>&1; then
            echo "Ollama server pronto (ollama status ok)."
            return 0
        fi
        sleep 2
        waited=$((waited+2))
    done

    echo "Aviso: não foi possível confirmar readiness do Ollama após $timeout_sec segundos. Verifique o log: $OLLAMA_LOG" >&2
    return 1
}

# Tenta iniciar o servidor (não faz o script morrer caso falhe)
start_ollama_server || true

# Baixar modelo Ollama
echo ""
echo "=== Download do Modelo Ollama ==="
if [ "$HAVE_INTERNET" -eq 1 ] && command -v ollama >/dev/null 2>&1; then
    if select_model; then
        if confirm "Deseja baixar o modelo '$SELECTED_MODEL' (${OLLAMA_MODELS[$SELECTED_MODEL]})?"; then
            echo "Baixando modelo $SELECTED_MODEL..."
            ollama pull "$SELECTED_MODEL"
            echo "Modelo baixado com sucesso!"
        else
            echo "Pulando download do modelo conforme solicitado."
            echo "Você pode baixá-lo manualmente com: ollama pull $SELECTED_MODEL"
        fi
    else
        echo "Nenhum modelo selecionado para download."
    fi
else
    if [ "$HAVE_INTERNET" -eq 0 ]; then
        echo "Sem internet: não é possível baixar o modelo agora."
    else
        echo "Ollama não está instalado. Instale-o primeiro."
    fi
fi

# Criar ambiente virtual se não existir
echo ""
echo "=== Criação do Ambiente Virtual Python ==="
if [ ! -d "$VENV_DIR" ]; then
    echo "Criando ambiente virtual em: $VENV_DIR"
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
else
    echo "Ambiente virtual já existe em: $VENV_DIR"
fi

echo "Ativando ambiente virtual temporariamente para instalar pacotes Python..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

# Instala pacotes Python para Flask + Ollama
echo "Instalando pacotes Python: Flask, requests"
python -m pip install --upgrade pip setuptools wheel
python -m pip install Flask requests

deactivate || true

echo ""
echo "=== Concluído ==="
echo "Ambiente virtual criado em: $VENV_DIR"
echo ""
echo "PRÓXIMOS PASSOS:"
echo ""
echo "1. O script tentou iniciar o serviço 'ollama serve' em background (se disponível)."
echo "   Log: $OLLAMA_LOG"
echo "   PID: $OLLAMA_PIDFILE"
echo "   Se preferir iniciar manualmente, pare o processo e rode: ollama serve"
echo ""
echo "2. Em outro terminal, ativar o ambiente e executar o servidor Flask:"
echo "   source $VENV_DIR/bin/activate"
echo "   python ollama_esp_server.py"
echo ""
echo "3. Testar o servidor (em outro terminal):"
echo "   curl -X POST http://localhost:5005/ask_stream -H 'Content-Type: application/json' -d '{\"question\": \"Olá\"}'"
echo ""
echo "Observações:"
echo " - Ollama rodará em http://localhost:11434"
echo " - Servidor Flask rodará em http://0.0.0.0:5005"
if [ -n "${SELECTED_MODEL:-}" ]; then
    echo " - Modelo instalado: $SELECTED_MODEL"
else
    echo " - Nenhum modelo instalado via script"
fi