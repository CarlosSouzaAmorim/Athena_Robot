#!/bin/bash
# Script de configuração do ambiente Python e download opcional de modelos llama

set -euo pipefail

MODEL_BASE="$HOME/Athena/_VOZES"
MODEL_BASE="$HOME/__ATHENA_VOZ_GPT"

FULL_MODEL_DIR="$MODEL_BASE/vosk-model-pt-fb-v0.1.1-20220516_2113"
FULL_MODEL_ZIP="vosk-model-pt-fb-v0.1.1-20220516_2113.zip"
FULL_MODEL_URL="https://alphacephei.com/vosk/models/$FULL_MODEL_ZIP"
FULL_MODEL_SIZE="~1.6GB"

SMALL_MODEL_DIR="$MODEL_BASE/vosk-model-small-pt-0.3"
SMALL_MODEL_ZIP="vosk-model-small-pt-0.3.zip"
SMALL_MODEL_URL="https://alphacephei.com/vosk/models/$SMALL_MODEL_ZIP"
SMALL_MODEL_SIZE="~31MB"

VENV_DIR="$HOME/athena_voz_ambiente_virtual/venv"
VENV_DIR="$HOME/esp32_llama_virtual_1/venv"

REQUIRED_APT_PACKAGES=(python3 python3-venv python3-pip ffmpeg libasound2-dev portaudio19-dev libffi-dev libssl-dev build-essential unzip)
SYSTEM_PYPAUDIO_PKG="python3-pyaudio"

# Funções utilitárias
check_internet() {
    if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1 && curl -sSf --connect-timeout 5 https://alphacephei.com >/dev/null 2>&1; then
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

downloader() {
    local url="$1" local out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -c "$url" -O "$out"
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar "$url" -o "$out"
    else
        echo "Erro: nem 'wget' nem 'curl' estão disponíveis para baixar arquivos." >&2
        return 1
    fi
}

download_and_unzip() {
    local url="$1" local zipfile="$2" local dest_dir="$3"
    mkdir -p "$(dirname "$zipfile")"
    echo "Baixando $url ..."
    downloader "$url" "$zipfile"
    echo "Descompactando $zipfile ..."
    unzip -q "$zipfile" -d "$(dirname "$zipfile")"
    rm -f "$zipfile"
    if [ ! -d "$dest_dir" ]; then
        echo "Erro: descompactação não criou o diretório esperado: $dest_dir" >&2
        return 1
    fi
    echo "Modelo instalado em: $dest_dir"
    return 0
}

# Início do script
echo "=== Configuração do ambiente Athena (voz) ==="
mkdir -p "$MODEL_BASE"

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
        # instalar pacote do sistema para PyAudio (melhora compatibilidade)
        sudo apt-get install -y "$SYSTEM_PYPAUDIO_PKG" || true
    else
        echo "Pulando instalação via apt conforme solicitado."
    fi
else
    echo "Sem internet: pule apt/install de dependências. Instale manualmente se necessário."
fi

# Baixar ambos os modelos (se faltarem)

# Testa se leve está presente
if [ ! -d "$SMALL_MODEL_DIR" ]; then
    SMALL_MODEL_PRESENT="Ausente"
else
    SMALL_MODEL_PRESENT="Presente"
    echo "Modelo leve já presente: $SMALL_MODEL_DIR"
fi
# Baixa completo se necessário
if [ ! -d "$FULL_MODEL_DIR" ]; then
    FULL_MODEL_PRESENT="Ausente"
else
    FULL_MODEL_PRESENT="Presente"
    echo "Modelo completo já presente: $FULL_MODEL_DIR"
fi


if [ -d "$FULL_MODEL_DIR" ] && [ -d "$SMALL_MODEL_DIR" ]; then
    echo "Ambos os modelos já estão presentes em: $MODEL_BASE"
else
    if [ "$HAVE_INTERNET" -eq 0 ]; then
        echo "Sem internet: não é possível baixar modelos agora. Coloque-os manualmente em: $MODEL_BASE"
    else
        echo "OPÇÕES PARA BAIXAR modelos Vosk em $MODEL_BASE."
        echo "Opções de download:"
        echo "  1) Modelo leve (~31MB): $SMALL_MODEL_URL ($SMALL_MODEL_PRESENT)"
        echo "  2) Modelo completo (~1.6GB): $FULL_MODEL_URL ($FULL_MODEL_PRESENT)"
        echo "  3) Baixar ambos os Modelos completo (~1.63GB)"
        echo "  4) Pular download (vou fornecer o modelo manualmente depois)"

        if [ "$HAVE_INTERNET" -eq 0 ]; then
            echo "Sem internet: download não disponível agora. Escolha 4 para pular."
            choice=4
        else
            read -r -p "Escolha 1/2/3/4: " choice
        fi
        case "$choice" in
            1)
                echo "Você escolheu o modelo leve (~31MB). Confirme para iniciar o download."
                if confirm "Confirmar download do modelo leve ($SMALL_MODEL_SIZE)?"; then
                    download_and_unzip "$SMALL_MODEL_URL" "$MODEL_BASE/$SMALL_MODEL_ZIP" "$SMALL_MODEL_DIR"
                else
                    echo "Download cancelado pelo usuário."
                fi
                ;;
            2)
                echo "Você escolheu o modelo completo (~1.6GB). Confirme para iniciar o download."
                if confirm "Confirmar download do modelo completo ($FULL_MODEL_SIZE)?"; then
                    download_and_unzip "$FULL_MODEL_URL" "$MODEL_BASE/$FULL_MODEL_ZIP" "$FULL_MODEL_DIR"
                else
                    echo "Download cancelado pelo usuário."
                fi
                ;;
            3)
                echo "Você escolheu ambos os modelos (~1.63GB). Confirme para iniciar o download."
                if confirm "Confirmar download do modelo completo ($FULL_MODEL_SIZE)?"; then
                    download_and_unzip "$SMALL_MODEL_URL" "$MODEL_BASE/$SMALL_MODEL_ZIP" "$SMALL_MODEL_DIR"
                    download_and_unzip "$FULL_MODEL_URL" "$MODEL_BASE/$FULL_MODEL_ZIP" "$FULL_MODEL_DIR"
                else
                    echo "Download cancelado pelo usuário."
                fi
                ;;
            *)
                echo "Pulando download de modelos. Coloque os modelos em $MODEL_BASE manualmente se desejar."
                ;;
        esac
    fi
fi


# Criar ambiente virtual se não existir
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

# Instala pacotes Python recomendados
echo "Instalando pacotes Python no venv: vosk sounddevice numpy pyserial psutil"
python -m pip install --upgrade pip setuptools wheel
python -m pip install vosk sounddevice numpy pyserial psutil

# PyAudio: tentar instalar via pip (pode falhar se dependências do sistema faltarem)
if confirm "Deseja tentar instalar PyAudio e bibliotecas TTS (PyAudio, pyttsx3, gTTS)?"; then
    python -m pip install PyAudio pyttsx3 gTTS SpeechRecognition
else
    echo "Pulando instalação opcional de PyAudio/TTS."
fi

deactivate || true

# Testa se leve está presente
if [ ! -d "$SMALL_MODEL_DIR" ]; then
    SMALL_MODEL_PRESENT="Ausente"
else
    SMALL_MODEL_PRESENT="Presente"
    echo "Modelo leve já presente: $SMALL_MODEL_DIR"
fi
# Baixa completo se necessário
if [ ! -d "$FULL_MODEL_DIR" ]; then
    FULL_MODEL_PRESENT="Ausente"
else
    FULL_MODEL_PRESENT="Presente"
    echo "Modelo completo já presente: $FULL_MODEL_DIR"
fi


echo ""
echo "=== Concluído ==="
echo "Modelos (se baixados) estão em: $MODEL_BASE"
echo "Ambiente virtual criado em: $VENV_DIR"
echo "Para ativar o ambiente virtual: source $VENV_DIR/bin/activate"
echo "Observações:"
echo " - Modelo leve: $SMALL_MODEL_SIZE ($SMALL_MODEL_PRESENT)"
echo " - Modelo completo: $FULL_MODEL_SIZE ($FULL_MODEL_PRESENT)"
echo " - Se precisar baixar modelos manualmente, coloque-os em: $MODEL_BASE"
