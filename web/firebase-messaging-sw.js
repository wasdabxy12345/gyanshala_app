importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyAK7dRifiX0mtogUJknS-hfQIsFqWkD42M",
  authDomain: "gyanshalaapp.firebaseapp.com",
  projectId: "gyanshalaapp",
  storageBucket: "gyanshalaapp.firebasestorage.app",
  messagingSenderId: "279965298426",
  appId: "1:279965298426:web:ffd1072dd9882a7f252343",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("Received background message ", payload);
});