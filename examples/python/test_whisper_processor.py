import whisper_processor

try:
    result = whisper_processor.process_audio("../../samples/jfk.wav", "base.en")
    print(result)
except Exception as e:
    print(f"Error: {e}")

