🩸 JeevanLink: AI-Based Urgent Blood Match and Alert System

🚀 Overview

JeevanLink is an AI-powered emergency response system designed to connect blood donors with recipients in critical situations.
The system intelligently identifies urgency, filters eligible donors based on location and availability, and sends real-time alerts to ensure faster response.


---

🎯 Problem Statement

In emergency situations, finding a compatible blood donor quickly is a major challenge.
Traditional systems are slow, manual, and lack real-time coordination.

👉 JeevanLink solves this by using AI + real-time communication + location tracking.


---

💡 Key Features

🧠 AI-Based Urgency Detection
Classifies emergency level from user input (text/voice)

📍 Location-Based Donor Matching
Filters nearby eligible donors using GPS tracking

⚡ Real-Time Alerts
Sends instant notifications using FCM (Firebase Cloud Messaging)

📩 Multi-Channel Communication
Includes SMS fallback for critical alerts

🤖 AI Chatbot Support
Assists users with onboarding and eligibility guidance

🔐 Secure Authentication
OTP-based login system for safe access



---

🛠️ Tech Stack

Programming Language: Python

AI/ML: NLP, Machine Learning

Libraries: NumPy, Pandas, Scikit-learn

Backend: Flask / FastAPI (if used, adjust)

Notifications: Firebase Cloud Messaging (FCM)

Messaging: Twilio API (SMS alerts)

Location Services: GPS Integration



---

🧩 System Architecture

1. User submits request (text/voice)


2. AI model analyzes urgency


3. System fetches nearby donors using location data


4. Alerts sent via FCM + SMS


5. Donors respond → system tracks availability




---

📊 Key Contributions

Designed an AI-driven emergency response system

Implemented real-time notification pipeline

Integrated multi-modal communication channels

Built scalable logic for donor matching and filtering



---

🔐 Environment Variables

This project uses environment variables for security.

Create a .env file in the root directory:

TWILIO_ACCOUNT_SID=your_sid_here
TWILIO_AUTH_TOKEN=your_token_here
FIREBASE_API_KEY=your_key_here

> ⚠️ Note: Sensitive credentials are not included in this repository.




---

▶️ How to Run

git clone https://github.com/SaniyaAfzali/Jeevanlink
cd jeevanlink
pip install -r requirements.txt
python app.py


---

📌 Future Improvements

Mobile app integration (React Native)

Advanced AI model for better accuracy

Real-time donor tracking dashboard

Integration with hospital databases



---

📄 Publication

This project is based on our research paper:

“JeevanLink: AI-Based Urgent Blood Match and Alert System”
Published in International Scientific Journal of Engineering Research (2026)


---

👩‍💻 Author

Saniya Afzali
AI/ML Student | Developer


---

⭐ Why This Project Matters

This system has the potential to save lives by reducing response time in emergency blood requirements using intelligent automation.
