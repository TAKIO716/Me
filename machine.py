import json
import random
import nltk
import re
import numpy as np
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.naive_bayes import MultinomialNB
#import library yang dibutuhkan untuk membuat chatbot

from google.colab import files
uploaded = files.upload()


with open('databaru1.json') as file:
    data = json.load(file)
# Baca file datachat yang sudah kita buat

all_patterns = []
all_tags = []
responses = {}
# Siapkan data training

for intent in data['intents']:
    for pattern in intent['patterns']:
        all_patterns.append(pattern)
        all_tags.append(intent['tag'])
    responses[intent['tag']] = intent['responses']


def simple_tokenizer(text):
    return re.findall(r'\b\w+\b', text.lower())
# fungsi untuk Vektorisasi teks

vectorizer = CountVectorizer(tokenizer=simple_tokenizer)
X = vectorizer.fit_transform(all_patterns)
y = all_tags
# Inisialisasi nilai X dan Y, dimana X dengan pattern dan Y dengan tag

model = MultinomialNB()
model.fit(X, y)
# Training model

def chatbot_response(user_input, threshold=0.1):
    user_vec = vectorizer.transform([user_input])
    proba = model.predict_proba(user_vec)[0]
    max_proba = np.max(proba)

    if max_proba < threshold:
        return "Maaf data yang anda cari tidak terdapat dalam datachat kami"
    else:
        tag = model.predict(user_vec)[0]
        return responses[tag][0]  # AMBIL RESPON PERTAMA SAJA, TIDAK RANDOM


#def chatbot_response(user_input):
 #   user_vec = vectorizer.transform([user_input])
  #  tag = model.predict(user_vec)[0]

# Fungsi untuk membalas chat yang akan di input oleh user


print("Dora Bitha: Halo! perkenalkan saya Dora Bitha. Tekan tombol 'x' untuk keluar.")
while True:
    user_input = input("Anda        : ")
    if user_input.lower() == 'x':
        print("Dora Bitha : Terima kasih sudah berkunjung dan sampai jumpa!")
        break
    response = chatbot_response(user_input)
    print("Dora Bitha :", response)
# Ini merupakan perulangan ketika chat dimulai dan diberikan opsi exit untuk mengakhiri program
