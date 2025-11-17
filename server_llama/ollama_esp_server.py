from flask import Flask, request, Response
import requests
import json

app = Flask(__name__)
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma3:1b"

@app.route("/model", methods=["GET"])
def get_model():
    return json.dumps({"model": MODEL}), 200, {"Content-Type": "application/json"}

@app.route("/ask_stream", methods=["POST"])
def ask_stream():
    data = request.get_json()
    question = data.get("question", "")

    payload = {
        "model": MODEL,
        "prompt": question,
        "stream": True
    }

    # Stream Ollama output → ESP32
    def generate():
        with requests.post(OLLAMA_URL, json=payload, stream=True) as r:
            for line in r.iter_lines():
                if line:
                    yield line + b"\n"

    return Response(generate(), mimetype="text/plain")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5005)

