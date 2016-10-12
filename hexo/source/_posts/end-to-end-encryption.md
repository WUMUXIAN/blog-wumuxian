---
title: How to design an end-to-end encryption
date: 2016-10-12 16:44:45
tags:
  - Asymmetric Encryption
  - Symmetric Encryption
  - Cryptograhy
category:
  - Security
---

An end-to-end encryption is a concept that requires the following conditions to be meet:

1. All data in transit are encrypted.
2. Only the intended users can decrypt the data using the cryptographic keys.
3. Even the service provider itself doesn't have the ability to decrypt the data.

The benifit of end-to-end encryption is obvious, it makes the data secure from potential eavesdroppers, evil database administrator and compromising of databases. It's very suitable for applications such as instant messaging, sensitive information and document storage and etc.

The design will vary slightly in different applications but the princples are the same, in this article we will try to design cloud storage service that meets the requirement of end-to-end encryption. Whereby the files uploaded by a certain user will be encrypted and can only be decrypted by the user himself or other users that he grant access to.

### Encryption Algorithms

Let's first look into what make these possible, the encryption algorithms. Generally speaking, an encryption is a series of steps that mathematically transforms plain text or other intelligible information into unintelligible cipher text. An encryption algorithm works together with a key, to encrypt and decrypt data. And we can differentiate them into two categories according to how the keys are used.

- Symmetric: The same key will be used to encrypt and decrypt the data
- Asymmetric: One public key is used to encrypt the data and one private key is used to decrypt the data

The symmetric encryption is fast, and hard to crack, however it's a big problem to transit the encryption key securely. The asymmetric encryption is much more expensive in CPU resources but it makes it possible to distrubte the public key freely without worrying about data gets decrypted as long as the private key is kept secret.

### Combining the Two Algorithms

Give it a thought for our cloud storage application. If we only use symmetric encryption to encrypt the file with a key that on the user knows and upload it to server, it seems that we have meet our requirements because now the server can't read the file and the user can read it, however it will not allow sharing the file safely among different users:

- If the user wants to give access to another user, he will have to pass the file key to him in some way. And there will be no secure way to do it.

Having known that using symmetric encryption along is not gonna make it, let's see whether the asymmetric encryption can get it to work. The file will be encrypted by the user's public key and send to server, this means that the file can only be decrypted by the user's private key, now let's assuming that this user A wants to give access to another user B, here's what happened:

1. User A will retrive the target file and user B's public key from server.
2. User A will decrypt the file, encrypt it again with user B's public key and upload to server.
3. Now User B will have a copy of the file encrypted with his public key, thus he gain the access to the file because he can decrypt it using his private key.

This looks just nice right, we have meet all of our requirements securely. However, there's a prolbem here:

- The file can get very huge, for example, a large video. And then the asymmetric can get so slow that it's no longer applicable, the traffic overhead will also be huge because each time one user wants to give access to another, it's a round trip for file between the client and the server.

As we can see using these algorithms along won't lead us to the goal, however combining them together will just solve the problem nicely.

