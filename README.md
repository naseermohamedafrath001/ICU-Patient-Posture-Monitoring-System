# ThermalVision AI+ - Patient Monitoring System

ThermalVision AI is an intelligent healthcare monitoring system (Mobile App) designed to assist nurses and healthcare providers in patient care. It utilizes computer vision and AI to analyze patient movements and positions from images and videos, providing real-time alerts and insights to ensure patient safety and skin integrity.

![Image](https://github.com/user-attachments/assets/710a3fee-bf78-402b-8a35-ed13b04fc492)

![Image](https://github.com/user-attachments/assets/fdb159c0-4af3-4d0a-9d6f-f78f52402781)

![Image](https://github.com/user-attachments/assets/841ab113-120e-44d8-a215-bcc36cd640a3)

![Image](https://github.com/user-attachments/assets/0086ec9c-55b1-45ca-9c99-e984703ca564)


## 🚀 Key Features

- **AI-Powered Analysis**: Automatically detects patient positions (Supine, Left Lateral, Right Lateral) using a deep learning model.
- **Real-Time Patient Monitoring**: Analyzes video streams in real-time to detect prolonged lack of movement.
- **Smart Alert System**: Triggers immediate desktop and mobile notifications when a patient remains in the same position for too long, helping prevent pressure sores.
- **Nurse Chat & Collaboration**: Built-in chat system for nurses to communicate and coordinate care.
- **Online Status Tracking**: Heartbeat-based system to monitor which healthcare providers are currently active.
- **Doctor Duty Management**: Real-time tracking of doctors on duty and their specialties.
- **Analytics Dashboard**: Visualizes system performance, patient distribution, and response times.

## 🛠️ Technology Stack

### Backend
- **Framework**: Flask (Python)
- **AI/ML**: PyTorch, Keras, OpenCV, NumPy
- **Database**: SQLite
- **Features**: RESTful API, Real-time streaming analysis (NDJSON)

### Frontend
- **Framework**: Flutter (Dart)
- **Design**: Minimalist & Premium UI with Gilroy typography
- **Platforms**: Android, iOS, Web, Windows
- **State Management**: Service-based architecture with SharedPreferences

## 📋 Prerequisites

- **Python 3.8+**
- **Flutter SDK** (Channel Stable)

## 📥 Installation & Setup

### 1. Clone the repository
```bash
git clone <repository-url>
cd <repository-folder>
```

### 2. Backend Setup
```bash
# Install dependencies
pip install -r Requirments.txt

# Start the Flask server
python app.py
```

### 3. Frontend Setup
```bash
cd flutter_app

# Install Flutter dependencies
flutter pub get

# Run the application
flutter run
```

### Guild for View
--------------

First, Backend connection:

	1. download the project file : https://github.com/naseermohamedafrath001/ICU-Patient-Posture-Monitoring-App-TAi-
	2. in the vs code terminal, run
		# Install dependencies
		pip install -r Requirments.txt

		# Start the Flask server
		python app.py
	3. if connected, u can see like below,
		* Debugger is active!
 		* Debugger PIN: 628-025-778	

Next App connection:

	1. install "ICU App.apk" on ur mobile phone.
	2. open app, in the login page u can see setting icon on the corner, click that and past "http://<your ip address>:Port" this url
	3. to get url,
		a. open windows terminal
		b. search "ipconfig"
		c. it will show ur ipv4 address like "eg:- 172.56.66.78"
		d. copy and past it on ur "your ip address"

** use same wifi connection both mobile and ur pc

## 📖 How to Use

1. **Login**: Use the designated nurse or admin credentials.
2. **Analysis**:
   - Navigate to the **Analysis** tab.
   - Upload an image or video/record a session.
   - Select the patient and start the AI analysis.
3. **Alerts**:
   - If the AI detects a stationary patient for a dangerous duration, a popup will appear.
   - Click **Acknowledge** to silence the alert and record your response.
4. **Chat**:
   - Use the **Message** section to communicate with other online nurses.
5. **Analytics**:
   - Check the **System Insights** on the dashboard for overall ward activity.

## 👥 Contributors

- **Team FYP**: Mohamed Ansaff, Asiyan Bahakiry, Naseer Mohamed Afrath (mohamednaseermohamedafrath@gmail.com)
- **Advisor**: Assoc.Prof.Dr.Umi Kalsom Yusof

---
*Created for Advanced Healthcare Monitoring - 2026 Final Year Project (FYP)*
