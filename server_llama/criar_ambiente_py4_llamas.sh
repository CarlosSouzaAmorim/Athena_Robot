#!/bin/bash
# Script de configuração do ambiente Python para Flask + Ollama ESP32 server

set -euo pipefail

MODEL_BASE="$HOME/Athena/_VOZES"

VENV_DIR="$HOME/esp32_ollama_virtual/venv"
REQUIRED_APT_PACKAGES=(python3 python3-venv python3-pip curl wget)

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

# Baixar modelo Ollama
echo ""
echo "=== Download do Modelo Ollama ==="
if [ "$HAVE_INTERNET" -eq 1 ] && command -v ollama >/dev/null 2>&1; then
    if confirm "Deseja baixar o modelo gemma3:1b (~800MB)?"; then
        echo "Baixando modelo gemma3:1b..."
        ollama pull gemma3:1b
        echo "Modelo baixado com sucesso!"
    else
        echo "Pulando download do modelo conforme solicitado."
        echo "Você pode baixá-lo manualmente com: ollama pull gemma3:1b"
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
echo "1. Iniciar o serviço Ollama (em um terminal separado):"
echo "   ollama serve"
echo ""
echo "2. Em outro terminal, ativar o ambiente e executar o servidor Flask:"
echo "   source $VENV_DIR/bin/activate"
#source /home/amorim/esp32_ollama_virtual/venv/bin/activate
echo "   python ollama_esp_server.py"
echo ""
echo "3. Testar o servidor (em outro terminal):"
echo "   curl -X POST http://localhost:5005/ask_stream -H 'Content-Type: application/json' -d '{\"question\": \"Olá\"}'"
echo ""
echo "Observações:"
echo " - Ollama rodará em http://localhost:11434"
echo " - Servidor Flask rodará em http://0.0.0.0:5005"
echo " - Modelo instalado: gemma3:1b"