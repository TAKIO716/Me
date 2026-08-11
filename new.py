import json
import random
import re
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import urllib.request

# Download JSON
url = "https://raw.githubusercontent.com/TAKIO716/Me/refs/heads/main/brownies.json"

try:
    urllib.request.urlretrieve(url, "brownies.json")
except Exception as e:
    print(f"Gagal download: {e}")
    exit()

with open('brownies.json', 'r', encoding='utf-8') as file:
    data = json.load(file)

all_patterns = []
all_tags = []
responses = {}

for intent in data['intents']:
    if 'tag' not in intent or 'patterns' not in intent or 'responses' not in intent:
        continue
    for pattern in intent['patterns']:
        all_patterns.append(pattern)
        all_tags.append(intent['tag'])
    responses[intent['tag']] = intent['responses']

def simple_tokenizer(text):
    # Normalize dulu
    text = text.lower()
    # Hapus tanda baca
    text = re.sub(r'[^\w\s]', ' ', text)
    # Split jadi kata
    words = text.split()
    # Remove stopword dasar bahasa indo
    stopwords = {'yang', 'itu', 'ini', 'dan', 'atau', 'dengan', 'untuk', 'dari', 'ke', 'di', 'pada', 'adalah', 'juga', 'sudah', 'akan', 'bisa', 'ga', 'gak', 'nggak', 'tidak', 'sih', 'dong', 'ya', 'deh', 'lah', 'kah', 'kok', 'bro', 'kak', 'min'}
    words = [w for w in words if w not in stopwords and len(w) > 1]
    return words

# Pake TF-IDF bukan CountVectorizer
vectorizer = TfidfVectorizer(
    tokenizer=simple_tokenizer,
    lowercase=True,
    ngram_range=(1, 2)  # Ambil 1 kata dan 2 kata berurutan
)

X = vectorizer.fit_transform(all_patterns)

def chatbot_response(user_input, threshold=0.3):
    user_vec = vectorizer.transform([user_input])
    
    # Hitung similarity ke semua pattern
    similarities = cosine_similarity(user_vec, X)[0]
    
    max_sim = np.max(similarities)
    
    if max_sim < threshold:
        return "Maaf data yang anda cari tidak terdapat dalam datachat kami"
    
    # Ambil index yang paling mirip
    best_idx = np.argmax(similarities)
    tag = all_tags[best_idx]
    
    return random.choice(responses[tag])

BOT_NAME = "Nova"

print(f"{BOT_NAME}: Halo! perkenalkan saya {BOT_NAME}. Tekan tombol 'x' untuk keluar.")
while True:
    user_input = input("Anda        : ")
    if user_input.lower() == 'x':
        print(f"{BOT_NAME}: Terima kasih sudah berkunjung dan sampai jumpa!")
        break
    response = chatbot_response(user_input)
    print(f"{BOT_NAME}:", response)
  
