import os
import io
import torch
import torch.nn as nn
from torchvision import models
import torchvision.transforms as T
from PIL import Image
import numpy as np
from flask import Flask, request, jsonify, Response, stream_with_context, send_from_directory, render_template_string
from flask_cors import CORS
import tempfile
import cv2
import json
from datetime import datetime
import sqlite3
import sys
import shutil
import time

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Persistence configuration
DATA_DIR = os.path.join(os.path.expanduser('~'), '.thermalvision_data')
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, 'history.db')
TMP_DIR = os.path.join(DATA_DIR, 'tmp')
os.makedirs(TMP_DIR, exist_ok=True)
tempfile.tempdir = TMP_DIR

UPLOAD_FOLDER = os.path.join(DATA_DIR, 'uploads')
CHAT_AUDIO_FOLDER = os.path.join(UPLOAD_FOLDER, 'chat_audio')
os.makedirs(CHAT_AUDIO_FOLDER, exist_ok=True)

print(f"DEBUG: DATA_DIR = {DATA_DIR}")
print(f"DEBUG: DB_PATH = {DB_PATH}")
print(f"DEBUG: TMP_DIR = {TMP_DIR}")
print(f"DEBUG: CWD = {os.getcwd()}")

# Move existing DB from project root if it exists (to fix reload issue)
if os.path.exists('history.db') and not os.path.exists(DB_PATH):
    try:
        import shutil
        shutil.move('history.db', DB_PATH)
        print(f"Moved existing database to {DB_PATH}")
    except Exception as e:
        print(f"Error moving database: {e}")

@app.route('/')
def index():
    try:
        with open('index.html', 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        return f"Error loading dashboard: {str(e)}", 500

@app.route('/<path:path>')
def serve_static(path):
    return send_from_directory('.', path)

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    conn.execute('''CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY, name TEXT, age INTEGER, room TEXT, condition TEXT, timestamp TEXT
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY, patient_id TEXT, patient_name TEXT, position TEXT, 
        duration TEXT, type TEXT, timestamp TEXT, acknowledged_by TEXT, status TEXT,
        analysis_result TEXT
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS nurses (
        username TEXT PRIMARY KEY, password TEXT, name TEXT, role TEXT, photo_url TEXT,
        phone TEXT, nurse_id TEXT, joined_date TEXT, address TEXT, is_online INTEGER DEFAULT 0
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS doctors (
        id TEXT PRIMARY KEY, name TEXT, position TEXT, specialty TEXT, 
        duty_time TEXT, joined_date TEXT, contact TEXT, photo_url TEXT
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_username TEXT,
        recipient_username TEXT,
        text TEXT,
        timestamp TEXT,
        is_read INTEGER DEFAULT 0,
        type TEXT DEFAULT 'text',
        media_url TEXT
    )''')

    # Migration: Add expanded fields to nurses if not exist
    cursor = conn.execute("PRAGMA table_info(nurses)")
    columns = [col[1] for col in cursor.fetchall()]
    new_cols = {
        'photo_url': 'TEXT',
        'phone': 'TEXT',
        'nurse_id': 'TEXT',
        'joined_date': 'TEXT',
        'address': 'TEXT',
        'is_online': 'INTEGER DEFAULT 0',
        'last_seen': 'TEXT'
    }
    for col_name, col_type in new_cols.items():
        if col_name not in columns:
            print(f"⚠️ Migrating nurses table: Adding {col_name} column")
            try:
                conn.execute(f"ALTER TABLE nurses ADD COLUMN {col_name} {col_type}")
            except Exception as e:
                print(f"Migration failed for {col_name}: {e}")

    # Seed nurses if empty
    cursor = conn.execute("SELECT COUNT(*) FROM nurses")
    if cursor.fetchone()[0] == 0:
        nurses = [
            ('admin', 'admin123', 'System Administrator', 'admin', '/assets/nurses/nurse_sarah.png'),
            ('nurse1', 'nurse123', 'Nurse Sarah', 'user', '/assets/nurses/nurse_sarah.png'),
            ('nurse2', 'nurse123', 'Nurse John', 'user', '/assets/nurses/nurse_john.png'),
            ('nurse3', 'nurse123', 'Nurse Emma', 'user', '/assets/nurses/nurse_emma.png'),
            ('nurse4', 'nurse123', 'Nurse Michael', 'user', '/assets/nurses/nurse_michael.png'),
            ('nurse5', 'nurse123', 'Nurse Olivia', 'user', '/assets/nurses/nurse_olivia.png'),
        ]
        conn.executemany("INSERT INTO nurses (username, password, name, role, photo_url) VALUES (?, ?, ?, ?, ?)", nurses)
        print("✅ Seeded 5 nurse accounts with photos.")

    # Seed doctors if empty
    cursor = conn.execute("SELECT COUNT(*) FROM doctors")
    if cursor.fetchone()[0] == 0:
        doctors = [
            ('doc1', 'Dr. Uroos Fatima', 'Senior Consultant', 'Psychiatrist', '14:00 - 16:30 PM', '2022-05-15', '+1234567890', '/assets/nurses/nurse_sarah.png'),
            ('doc2', 'Dr. David Bensoussan', 'Specialist', 'Cardiologist', '08:00 - 12:00 AM', '2021-10-20', '+9876543210', '/assets/nurses/nurse_john.png'),
            ('doc3', 'Dr. Sarah Wilson', 'Consultant', 'Neurologist', '10:00 - 14:00 PM', '2023-01-10', '+1122334455', '/assets/nurses/nurse_emma.png'),
            ('doc4', 'Dr. Michael Chen', 'Senior Surgeon', 'Orthopedic', '16:00 - 20:00 PM', '2020-03-05', '+5566778899', '/assets/nurses/nurse_michael.png'),
        ]
        conn.executemany("INSERT INTO doctors (id, name, position, specialty, duty_time, joined_date, contact, photo_url) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", doctors)
        print("✅ Seeded initial doctors data.")

    # Migration: Check if analysis_result column exists in alerts
    cursor = conn.execute("PRAGMA table_info(alerts)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'analysis_result' not in columns:
        print("⚠️ Migrating alerts table: Adding analysis_result column")
        try:
            conn.execute("ALTER TABLE alerts ADD COLUMN analysis_result TEXT")
        except Exception as e:
            print(f"Migration failed: {e}")

    conn.execute('''CREATE TABLE IF NOT EXISTS analysis_history (
        id TEXT PRIMARY KEY, timestamp TEXT, filename TEXT, file_type TEXT, 
        file_size INTEGER, prediction TEXT, confidence REAL, probabilities TEXT, 
        patient_id TEXT, notes TEXT, analysis_result TEXT
    )''')

    # Migration: Check if analysis_result column exists in analysis_history
    cursor = conn.execute("PRAGMA table_info(analysis_history)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'analysis_result' not in columns:
        print("⚠️ Migrating analysis_history table: Adding analysis_result column")
        try:
            conn.execute("ALTER TABLE analysis_history ADD COLUMN analysis_result TEXT")
        except Exception as e:
            print(f"Migration failed: {e}")

    # Migration: Check if type column exists in messages
    cursor = conn.execute("PRAGMA table_info(messages)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'type' not in columns:
        print("⚠️ Migrating messages table: Adding type and media_url columns")
        try:
            conn.execute("ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'text'")
            conn.execute("ALTER TABLE messages ADD COLUMN media_url TEXT")
        except Exception as e:
            print(f"Migration failed for messages: {e}")

    conn.commit()
    conn.close()

# Initialize DB on startup
try:
    init_db()
except Exception as e:
    print(f"Database initialization error: {e}")

# Load your model
def load_checkpoint(weights_path):
    try:
        ckpt = torch.load(weights_path, map_location="cpu")
        classes = ckpt.get("classes", ['supine', 'left', 'right'])
        img_size = int(ckpt.get("img_size", 224))
        state_dict = ckpt["state_dict"]
        return state_dict, classes, img_size
    except Exception as e:
        print(f"Error loading checkpoint: {e}")
        # Return default values if model loading fails
        return None, ['supine', 'left', 'right'], 224

def build_model(num_classes):
    model = models.resnet18(weights=None)
    model.fc = nn.Linear(model.fc.in_features, num_classes)
    model.eval()
    return model

def get_eval_transform(img_size):
    return T.Compose([
        T.Grayscale(num_output_channels=3),
        T.Resize(256),
        T.CenterCrop(img_size),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225]),
    ])

def predict_one(model, transform, img_data, class_names):
    try:
        if isinstance(img_data, str):
            img = Image.open(img_data).convert("L")
        else:
            img = Image.open(io.BytesIO(img_data)).convert("L")
        
        x = transform(img).unsqueeze(0)
        with torch.no_grad():
            logits = model(x)
            probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
        idx = int(np.argmax(probs))
        return class_names[idx], float(probs[idx]), probs.tolist()
    except Exception as e:
        raise Exception(f"Prediction error: {str(e)}")

# Initialize model
try:
    WEIGHTS_PATH = "best_model.pth"
    if os.path.exists(WEIGHTS_PATH):
        state_dict, classes, img_size = load_checkpoint(WEIGHTS_PATH)
        if state_dict:
            model = build_model(len(classes))
            model.load_state_dict(state_dict)
            model.eval()
            transform = get_eval_transform(img_size)
            print(f"✅ Model loaded successfully with classes: {classes}")
        else:
            raise Exception("State dict is None")
    else:
        raise FileNotFoundError(f"Model file {WEIGHTS_PATH} not found")
        
except Exception as e:
    print(f"❌ Error loading model: {e}")
    print("⚠️  Using fallback mode with default classes")
    classes = ['supine', 'left', 'right']
    model = None
    transform = None

def format_timestamp(seconds):
    """Convert seconds to MM:SS format"""
    minutes = int(seconds // 60)
    seconds = int(seconds % 60)
    return f"{minutes:02d}:{seconds:02d}"

def generate_movement_analysis(position_changes, frame_predictions, total_duration):
    """Generate detailed movement analysis"""
    if not position_changes:
        return {
            'movement_detected': False,
            'summary': 'No position changes detected during video',
            'is_consistent': True,
            'consistency_score': 1.0
        }
    
    # Calculate consistency
    total_frames = len(frame_predictions)
    if total_frames == 0:
        return {'movement_detected': False, 'summary': 'No frames analyzed'}
        
    # Group by prediction
    counts = {}
    for f in frame_predictions:
        pred = f['prediction']
        counts[pred] = counts.get(pred, 0) + 1
        
    dominant_pos = max(counts, key=counts.get)
    consistency = counts[dominant_pos] / total_frames
    
    return {
        'movement_detected': True,
        'summary': f'Movement detected: {len(position_changes)} position changes',
        'is_consistent': consistency > 0.8,
        'consistency_score': consistency,
        'dominant_position': dominant_pos
    }

def simulate_prediction():
    """Simulate prediction when model is not available"""
    import random
    positions = ['supine', 'left', 'right']
    pred_class = random.choice(positions)
    confidence = random.uniform(0.7, 0.95)
    probs = [random.uniform(0, 1) for _ in positions]
    probs[positions.index(pred_class)] = confidence
    # Normalize probabilities

@app.route('/predict', methods=['POST'])
def predict():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
        
    try:
        if model is None:
            return jsonify({'error': 'Model not loaded'}), 500
            
        img_bytes = file.read()
        prediction, confidence, probabilities = predict_one(model, transform, img_bytes, classes)
        
        # Create probability dict
        prob_dict = {classes[i]: float(probabilities[i]) for i in range(len(classes))}
        
        return jsonify({
            'prediction': prediction,
            'confidence': confidence,
            'probabilities': prob_dict,
            'all_classes': classes
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/predict_video', methods=['POST'])
def predict_video():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
        
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    # Save temp file
    temp_dir = tempfile.mkdtemp()
    temp_path = os.path.join(temp_dir, file.filename)
    file.save(temp_path)
    
    try:
        cap = cv2.VideoCapture(temp_path)
        ret, frame = cap.read()
        cap.release()
        
        if not ret:
            return jsonify({'error': 'Could not read video'}), 400
            
        # Convert BGR to RGB then to PIL Image
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(frame_rgb).convert("L")
        
        # Predict
        x = transform(img).unsqueeze(0)
        with torch.no_grad():
            logits = model(x)
            probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
        idx = int(np.argmax(probs))
        
        prob_dict = {classes[i]: float(probs[i]) for i in range(len(classes))}
        
        return jsonify({
            'prediction': classes[idx],
            'confidence': float(probs[idx]),
            'probabilities': prob_dict,
            'all_classes': classes,
            'note': 'Analysis based on first frame only'
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        shutil.rmtree(temp_dir)

@app.route('/predict_video_frames', methods=['POST'])
def predict_video_frames():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
        
    file = request.files['file']
    
    # Save temp file
    temp_dir = tempfile.mkdtemp()
    temp_path = os.path.join(temp_dir, file.filename)
    file.save(temp_path)
    
    try:
        cap = cv2.VideoCapture(temp_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = total_frames / fps
        
        # Analyze 1 frame per second
        frame_interval = int(fps)
        predictions = []
        
        current_frame = 0
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
                
            if current_frame % frame_interval == 0:
                # Process frame
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                img = Image.fromarray(frame_rgb).convert("L")
                
                x = transform(img).unsqueeze(0)
                with torch.no_grad():
                    logits = model(x)
                    probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
                idx = int(np.argmax(probs))
                
                timestamp = current_frame / fps
                
                predictions.append({
                    'frame_number': current_frame,
                    'timestamp': timestamp,
                    'timestamp_formatted': format_timestamp(timestamp),
                    'prediction': classes[idx],
                    'confidence': float(probs[idx])
                })
                
            current_frame += 1
            
        cap.release()
        
        # Analyze movement/changes
        position_changes = []
        if predictions:
            current_pos = predictions[0]['prediction']
            for i in range(1, len(predictions)):
                if predictions[i]['prediction'] != current_pos:
                    position_changes.append({
                        'from': current_pos,
                        'to': predictions[i]['prediction'],
                        'timestamp': predictions[i]['timestamp'],
                        'frame_number': predictions[i]['frame_number']
                    })
                    current_pos = predictions[i]['prediction']
        
        movement_analysis = generate_movement_analysis(position_changes, predictions, duration)
        
        # Calculate overall prediction (dominant)
        counts = {}
        for p in predictions:
            pred = p['prediction']
            counts[pred] = counts.get(pred, 0) + 1
        
        overall_prediction = max(counts, key=counts.get) if counts else "Unknown"
        overall_confidence = sum(p['confidence'] for p in predictions) / len(predictions) if predictions else 0
        
        return jsonify({
            'prediction': overall_prediction,
            'confidence': overall_confidence,
            'frame_predictions': predictions,
            'position_changes': position_changes,
            'movement_analysis': movement_analysis,
            'video_metadata': {
                'duration': duration,
                'total_frames': total_frames,
                'fps': fps
            }
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        shutil.rmtree(temp_dir)

@app.route('/predict_video_interval', methods=['POST'])
def predict_video_interval():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
        
    file = request.files['file']
    start_time = float(request.form.get('start_time', 0))
    end_time = float(request.form.get('end_time', 5))
    
    # Save temp file
    temp_dir = tempfile.mkdtemp()
    temp_path = os.path.join(temp_dir, file.filename)
    file.save(temp_path)
    
    try:
        cap = cv2.VideoCapture(temp_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        
        start_frame = int(start_time * fps)
        end_frame = int(end_time * fps)
        
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        
        predictions = []
        current_frame = start_frame
        
        # Analyze every 10th frame in interval for speed
        step = 10
        
        while current_frame < end_frame and cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
                
            if (current_frame - start_frame) % step == 0:
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                img = Image.fromarray(frame_rgb).convert("L")
                
                x = transform(img).unsqueeze(0)
                with torch.no_grad():
                    logits = model(x)
                    probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
                idx = int(np.argmax(probs))
                
                predictions.append({
                    'frame': current_frame,
                    'timestamp': current_frame / fps,
                    'prediction': classes[idx],
                    'confidence': float(probs[idx])
                })
            
            current_frame += 1
            
        cap.release()
        
        if not predictions:
            return jsonify({'error': 'No frames analyzed'}), 400
            
        # Determine dominant position
        counts = {}
        for p in predictions:
            pred = p['prediction']
            counts[pred] = counts.get(pred, 0) + 1
            
        dominant_pos = max(counts, key=counts.get)
        
        # Check if label changed within interval (micro-movement)
        label_changed = len(counts) > 1

        # Format timestamps in predictions
        for p in predictions:
            p['timestamp_formatted'] = format_timestamp(p['timestamp'])
        
        return jsonify({
            'interval_start': start_time,
            'interval_end': end_time,
            'dominant_position': dominant_pos,
            'label_changed': label_changed,
            'predictions': predictions
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        shutil.rmtree(temp_dir)

@app.route('/api/history', methods=['GET', 'POST'])
def handle_history():
    conn = get_db_connection()
    
    if request.method == 'POST':
        try:
            data = request.get_json()
            conn.execute('''INSERT INTO analysis_history 
                          (id, timestamp, filename, file_type, prediction, confidence, probabilities, patient_id, notes, analysis_result)
                          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                          (data['id'], data['timestamp'], data['filename'], data['file_type'],
                           data['prediction'], data['confidence'], json.dumps(data.get('probabilities', {})),
                           data.get('patient', {}).get('id'), data.get('movementSummary'),
                           data.get('analysis_result')))
            conn.commit()
            return jsonify({"status": "success", "message": "History saved"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
            
    else: # GET
        try:
            cursor = conn.execute('''
                SELECT h.*, h.patient_id as patientId, p.name as patient_name, p.name as patientName 
                FROM analysis_history h 
                LEFT JOIN patients p ON h.patient_id = p.id 
                ORDER BY h.timestamp DESC
            ''')
            history = [dict(row) for row in cursor.fetchall()]
            return jsonify(history)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route('/api/alert', methods=['POST'])
def save_alert():
    """Save alert information"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
            
        print(f"Alert received: {data}")
        
        conn = get_db_connection()
        conn.execute('''INSERT INTO alerts 
                      (id, patient_id, patient_name, position, duration, type, timestamp, acknowledged_by, status, analysis_result)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                      (data.get('id'), data.get('patientId'), data.get('patientName'), 
                       data.get('position'), data.get('duration'), data.get('type'),
                       data.get('timestamp'), data.get('acknowledgedBy'), data.get('status'),
                       data.get('analysis_result')))
        conn.commit()
        conn.close()
        
        return jsonify({
            "status": "success", 
            "message": "Alert logged",
            "alert_id": data.get('id')
        })
        
    except Exception as e:
        print(f"Error saving alert: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/alert/acknowledge', methods=['POST'])
def acknowledge_alert():
    """Acknowledge an alert"""
    try:
        data = request.get_json()
        if not data or 'id' not in data:
            return jsonify({"error": "No alert ID provided"}), 400
            
        print(f"Acknowledging alert: {data}")
        
        conn = get_db_connection()
        
        # Check if already acknowledged to prevent overwriting the first click
        cursor = conn.execute("SELECT status, acknowledged_by FROM alerts WHERE id = ?", (data.get('id'),))
        row = cursor.fetchone()
        
        if row and row['status'] == 'acknowledged':
            conn.close()
            return jsonify({
                "status": "already_acknowledged", 
                "message": f"Alert already acknowledged by {row['acknowledged_by']}",
                "acknowledged_by": row['acknowledged_by']
            }), 200

        conn.execute('''UPDATE alerts 
                      SET status = 'acknowledged', acknowledged_by = ?
                      WHERE id = ?''',
        (data.get('acknowledgedBy'), data.get('id')))
        conn.commit()
        conn.close()
        
        return jsonify({
            "status": "success", 
            "message": f"Alert {data.get('id')} acknowledged by {data.get('acknowledgedBy')}"
        })
        
    except Exception as e:
        print(f"Error acknowledging alert: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/alerts', methods=['GET'])
def get_alerts():
    try:
        status = request.args.get('status')
        conn = get_db_connection()
        query = 'SELECT a.*, a.patient_id as patientId, a.patient_name as patientName FROM alerts a'
        params = []
        
        if status:
            query += ' WHERE a.status = ?'
            params.append(status)
            
        query += ' ORDER BY a.timestamp DESC'
        
        cursor = conn.execute(query, params)
        alerts = [dict(row) for row in cursor.fetchall()]
        conn.close()
        return jsonify({
            "alerts": alerts,
            "total": len(alerts)
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "healthy",
        "model_loaded": model is not None,
        "classes": classes,
        "timestamp": datetime.now().isoformat(),
        "version": "2.0.0"
    })

@app.route('/api/login', methods=['POST'])
def login():
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        role = data.get('role')

        conn = get_db_connection()
        cursor = conn.execute("SELECT * FROM nurses WHERE username = ? AND password = ? AND role = ?", 
                           (username, password, role))
        nurse = cursor.fetchone()
        conn.close()

        if nurse:
            # Set online status and last seen
            conn = get_db_connection()
            conn.execute("UPDATE nurses SET is_online = 1, last_seen = ? WHERE username = ?", 
                         (datetime.now().isoformat(), username))
            conn.commit()
            conn.close()

            return jsonify({
                "status": "success",
                "user": {
                    "username": nurse['username'],
                    "name": nurse['name'],
                    "role": nurse['role'],
                    "photo_url": nurse['photo_url']
                }
            })
        else:
            return jsonify({"status": "error", "message": "Invalid credentials"}), 401
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/logout', methods=['POST'])
def logout():
    try:
        data = request.get_json()
        username = data.get('username')
        if not username:
            return jsonify({"error": "No username provided"}), 400
            
        conn = get_db_connection()
        conn.execute("UPDATE nurses SET is_online = 0, last_seen = NULL WHERE username = ?", (username,))
        conn.commit()
        conn.close()
        return jsonify({"status": "success", "message": "Logged out successfully"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/heartbeat', methods=['POST'])
def heartbeat():
    try:
        data = request.get_json()
        username = data.get('username')
        if not username:
            return jsonify({"error": "No username provided"}), 400
            
        conn = get_db_connection()
        conn.execute("UPDATE nurses SET is_online = 1, last_seen = ? WHERE username = ?", 
                     (datetime.now().isoformat(), username))
        conn.commit()
        conn.close()
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/nurses', methods=['GET', 'POST'])
def handle_nurses():
    conn = get_db_connection()
    if request.method == 'POST':
        try:
            data = request.get_json()
            conn.execute('''INSERT INTO nurses (username, password, name, role, photo_url, phone, nurse_id, joined_date, address)
                          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                          (data['username'], data['password'], data['name'], 
                           data.get('role', 'user'), data.get('photo_url', '/assets/nurses/nurse_sarah.png'),
                           data.get('phone', ''), data.get('nurse_id', ''),
                           data.get('joined_date', datetime.now().strftime('%Y-%m-%d')),
                           data.get('address', '')))
            conn.commit()
            return jsonify({"status": "success", "message": "Nurse added"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
    else: # GET
        try:
            cursor = conn.execute("SELECT username, name, role, photo_url, phone, nurse_id, joined_date, address FROM nurses")
            nurses = [dict(row) for row in cursor.fetchall()]
            return jsonify(nurses)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route('/api/nurses/<username>', methods=['PUT', 'DELETE'])
def update_delete_nurse(username):
    conn = get_db_connection()
    if request.method == 'DELETE':
        try:
            conn.execute('DELETE FROM nurses WHERE username = ?', (username,))
            conn.commit()
            return jsonify({"status": "success", "message": "Nurse deleted"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
    else: # PUT
        try:
            data = request.get_json()
            name = data.get('name')
            role = data.get('role')
            password = data.get('password')
            phone = data.get('phone', '')
            nurse_id = data.get('nurse_id', '')
            joined_date = data.get('joined_date', '')
            address = data.get('address', '')

            if not name or not role:
                return jsonify({"error": "Name and role are required"}), 400

            if password:
                conn.execute('''UPDATE nurses SET name = ?, role = ?, password = ?, phone = ?, nurse_id = ?, joined_date = ?, address = ? WHERE username = ?''',
                           (name, role, password, phone, nurse_id, joined_date, address, username))
            else:
                conn.execute('''UPDATE nurses SET name = ?, role = ?, phone = ?, nurse_id = ?, joined_date = ?, address = ? WHERE username = ?''',
                           (name, role, phone, nurse_id, joined_date, address, username))
            
            conn.commit()
            return jsonify({"status": "success", "message": "Nurse updated successfully"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route('/api/doctors', methods=['GET', 'POST'])
def handle_doctors():
    conn = get_db_connection()
    if request.method == 'POST':
        try:
            data = request.get_json()
            conn.execute('''INSERT INTO doctors (id, name, position, specialty, duty_time, joined_date, contact, photo_url)
                          VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
                          (data['id'], data['name'], data['position'], data['specialty'],
                           data.get('duty_time', ''), data.get('joined_date', ''), data.get('contact', ''),
                           data.get('photo_url', '/assets/nurses/nurse_sarah.png')))
            conn.commit()
            return jsonify({"status": "success", "message": "Doctor added"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
    else: # GET
        try:
            cursor = conn.execute("SELECT * FROM doctors")
            doctors = [dict(row) for row in cursor.fetchall()]
            return jsonify(doctors)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route('/api/doctors/<id>', methods=['PUT', 'DELETE'])
def update_delete_doctor(id):
    conn = get_db_connection()
    if request.method == 'DELETE':
        try:
            conn.execute('DELETE FROM doctors WHERE id = ?', (id,))
            conn.commit()
            return jsonify({"status": "success", "message": "Doctor deleted"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()
    else: # PUT
        try:
            data = request.get_json()
            conn.execute('''UPDATE doctors SET name = ?, position = ?, specialty = ?, duty_time = ?, joined_date = ?, contact = ? WHERE id = ?''',
                       (data['name'], data['position'], data['specialty'], data['duty_time'], data['joined_date'], data['contact'], id))
            conn.commit()
            return jsonify({"status": "success", "message": "Doctor updated successfully"})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
        finally:
            conn.close()

@app.route('/assets/nurses/<path:filename>')
def serve_nurse_photo(filename):
    return send_from_directory('assets/nurses', filename)

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

@app.errorhandler(413)
def too_large(error):
    return jsonify({'error': 'File too large'}), 413

# ==========================================
# CLI Utility Functions
# ==========================================

def sync_database():
    """Sync database from hidden directory to current directory for inspection"""
    print("🔄 ThermalVision Database Synchronizer")
    print("=" * 40)
    
    SOURCE_DB = DB_PATH
    DEST_DB = 'history_snapshot.db'
    
    if not os.path.exists(SOURCE_DB):
        print(f"❌ Source database not found at: {SOURCE_DB}")
        print("   Run the application first to create the database.")
        return

    try:
        # Create a copy
        shutil.copy2(SOURCE_DB, DEST_DB)
        
        # Get file stats
        size = os.path.getsize(DEST_DB) / 1024  # KB
        mtime = time.ctime(os.path.getmtime(DEST_DB))
        
        print(f"✅ Database synchronized successfully!")
        print(f"📂 Source: {SOURCE_DB}")
        print(f"📄 Dest:   {os.path.abspath(DEST_DB)}")
        print(f"📊 Size:   {size:.2f} KB")
        print(f"🕒 Time:   {mtime}")
        print("\n💡 You can now open 'history_snapshot.db' with your DB viewer.")
        print("   (Note: This file will not update automatically. Run this command again to refresh.)")
        
    except Exception as e:
        print(f"❌ Error synchronizing database: {e}")

def view_database():
    """View contents of the database"""
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found at: {DB_PATH}")
        return

    print(f"📂 Opening database: {DB_PATH}")
    print("="*60)
    
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # 0. View Nurses
        print("\n👩‍⚕️ NURSES TABLE")
        print("-" * 60)
        cursor.execute("SELECT username, name, role, photo_url FROM nurses")
        nurses = cursor.fetchall()
        if not nurses:
            print("No nurses found.")
        else:
            for n in nurses:
                print(f"User: {n['username']}, Name: {n['name']}, Role: {n['role']}, Photo: {n['photo_url']}")

        # 1. View Patients
        print("\n🏥 PATIENTS TABLE")
        print("-" * 60)
        cursor.execute("SELECT * FROM patients")
        patients = cursor.fetchall()
        if not patients:
            print("No patients found.")
        else:
            for p in patients:
                print(f"ID: {p['id']}, Name: {p['name']}, Condition: {p['condition']}")

        # 2. View Alerts
        print("\n⚠️  ALERTS TABLE")
        print("-" * 60)
        cursor.execute("SELECT * FROM alerts ORDER BY timestamp DESC LIMIT 5")
        alerts = cursor.fetchall()
        if not alerts:
            print("No alerts found.")
        else:
            for a in alerts:
                print(f"[{a['timestamp']}] {a['type']} - {a['patient_name']} ({a['position']})")

        # 3. View Analysis History
        print("\n📊 ANALYSIS HISTORY (Last 5)")
        print("-" * 60)
        cursor.execute("SELECT * FROM analysis_history ORDER BY timestamp DESC LIMIT 5")
        history = cursor.fetchall()
        if not history:
            print("No history records found.")
        else:
            for h in history:
                print(f"[{h['timestamp']}] {h['filename']} -> {h['prediction']} ({h['confidence']:.2f})")

        conn.close()
        print("\n" + "="*60)
        
    except Exception as e:
        print(f"❌ Error reading database: {e}")

def inspect_db():
    """Inspect database schema and export to JSON"""
    print(f"🔍 Inspecting database schema...")
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found at: {DB_PATH}")
        return

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        schema = {}
        
        # Get tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        
        for table in tables:
            table_name = table[0]
            cursor.execute(f"PRAGMA table_info({table_name});")
            columns = cursor.fetchall()
            schema[table_name] = [
                {"cid": col[0], "name": col[1], "type": col[2], "notnull": col[3], "dflt_value": col[4], "pk": col[5]}
                for col in columns
            ]
            
        conn.close()
        
        output_file = 'db_schema.json'
        with open(output_file, 'w') as f:
            json.dump(schema, f, indent=2)
            
        print(f"✅ Schema exported to {output_file}")
        
    except Exception as e:
        print(f"❌ Error inspecting database: {e}")

@app.route('/api/history/<id>', methods=['DELETE'])
def delete_history(id):
    try:
        conn = get_db_connection()
        conn.execute('DELETE FROM analysis_history WHERE id = ?', (id,))
        conn.commit()
        conn.close()
        print(f"Deleted history record: {id}")
        return jsonify({"status": "success", "message": "Record deleted"})
    except Exception as e:
        print(f"Error deleting history: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/alert/<id>', methods=['DELETE'])
def delete_alert(id):
    try:
        conn = get_db_connection()
        conn.execute('DELETE FROM alerts WHERE id = ?', (id,))
        conn.commit()
        conn.close()
        print(f"Deleted alert record: {id}")
        return jsonify({"status": "success", "message": "Alert deleted"})
    except Exception as e:
        print(f"Error deleting alert: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/history/all', methods=['DELETE'])
def clear_all_history():
    try:
        conn = get_db_connection()
        # Delete all records from both tables
        conn.execute('DELETE FROM analysis_history')
        conn.execute('DELETE FROM alerts')
        conn.commit()
        conn.close()
        print("Deleted all history and alerts")
        return jsonify({"status": "success", "message": "All history and alerts cleared"})
    except Exception as e:
        print(f"Error clearing history: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/stream_video_analysis', methods=['POST'])
def stream_video_analysis():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
        
    file = request.files['file']
    patient_id = request.form.get('patientId')
    patient_name = request.form.get('patientName')

    # Save temp file
    temp_dir = tempfile.mkdtemp()
    temp_path = os.path.join(temp_dir, file.filename)
    file.save(temp_path)

    return Response(
        stream_with_context(generate_analysis_stream(temp_path, patient_id, patient_name, is_file=True, cleanup_dir=temp_dir)),
        mimetype='application/x-ndjson'
    )


@app.route('/stream_rtsp_analysis', methods=['POST'])
def stream_rtsp_analysis():
    data = request.get_json()
    if not data or 'url' not in data:
        return jsonify({'error': 'No RTSP URL provided'}), 400
        
    rtsp_url = data['url']
    patient_id = data.get('patientId')
    patient_name = data.get('patientName')

    return Response(
        stream_with_context(generate_analysis_stream(rtsp_url, patient_id, patient_name, is_file=False)),
        mimetype='application/x-ndjson'
    )



def generate_analysis_stream(source, patient_id, patient_name, is_file=True, cleanup_dir=None):
    # Auto-detect if source is a local file
    source = source.strip().strip('"').strip("'")
    
    # Don't normalize RTSP/HTTP URLs as it breaks them on Windows
    if not (source.lower().startswith('rtsp://') or source.lower().startswith('http://') or source.lower().startswith('https://')):
        source = os.path.normpath(source)

    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        error_msg = f"Could not open source: {source}"
        print(f"ERROR: {error_msg}")
        yield json.dumps({'type': 'error', 'message': error_msg}) + '\n'
        return

    try:
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        if fps <= 0 or fps > 1000: # Handle weird OpenCV FPS values
            fps = 30 
            
        duration = total_frames / fps if total_frames > 0 else 0
        
        print(f"DEBUG: Starting stream analysis. Source: {source}, FPS: {fps}, Total Frames: {total_frames}, Duration: {duration}s")

        # Send initial metadata
        yield json.dumps({
            'type': 'metadata',
            'duration': duration,
            'fps': fps,
            'total_frames': total_frames,
            'isLive': False
        }) + '\n'

        # Real-time synchronization variables
        start_analysis_time = time.time()
        
        # Track process timing
        next_process_time = 0.0
        current_frame = 0
        
        previous_position = None
        stable_start_time = 0
        
        # Track alerts to avoid duplicates for same event
        last_alert_time = -10 

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            
            # Use MSEC for accurate video timing, fallback to frame-based for live/buggy streams
            msec = cap.get(cv2.CAP_PROP_POS_MSEC)
            timestamp = msec / 1000.0 if msec > 0 else (current_frame / fps)
                
            if timestamp >= next_process_time:
                # Process frame
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                img = Image.fromarray(frame_rgb).convert("L")
                
                x = transform(img).unsqueeze(0)
                with torch.no_grad():
                    logits = model(x)
                    probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
                idx = int(np.argmax(probs))
                prediction = classes[idx]
                confidence = float(probs[idx])
                
                # --- REAL-TIME SYNC ---
                # Ensure analysis doesn't run faster than the video itself
                elapsed_real_time = time.time() - start_analysis_time
                if timestamp > elapsed_real_time:
                    delay = timestamp - elapsed_real_time
                    time.sleep(delay)

                minutes = int(timestamp // 60)
                seconds = int(timestamp % 60)
                timestamp_formatted = f"{minutes:02}:{seconds:02}"

                # Increment for next second
                next_process_time += 1.0

                # --- ALERT LOGIC ---
                if prediction == previous_position:
                    # Position is stable
                    stable_duration = timestamp - stable_start_time
                    
                    # Check for 5s threshold
                    if stable_duration >= 5.0 and (timestamp - last_alert_time) > 5.0:
                        # TRIGGER ALERT
                        alert_id = f"alert_{int(time.time()*1000)}"
                        
                        # 1. Save to DB
                        try:
                            conn = get_db_connection()
                            conn.execute('''INSERT INTO alerts 
                                          (id, patient_id, patient_name, position, duration, type, timestamp, status, analysis_result)
                                          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                                          (alert_id, patient_id, patient_name, 
                                           prediction, f"{stable_duration:.1f}", 'No Movement Detected',
                                           datetime.now().isoformat(), 'pending',
                                           'Video Analysis'))
                            conn.commit()
                            conn.close()
                            print(f"Alert saved: {alert_id}")
                        except Exception as e:
                            print(f"Error saving alert: {e}")

                        # 2. Stream Alert Event
                        try:
                            yield json.dumps({
                                'type': 'alert',
                                'alert_id': alert_id,
                                'timestamp': timestamp,
                                'position': prediction,
                                'duration': stable_duration,
                                'message': f'Patient in {prediction} for {stable_duration:.1f}s'
                            }) + '\n'
                        except Exception as e:
                            print(f"Error yielding alert: {e}")
                            
                        last_alert_time = timestamp
                        
                else:
                    # Position changed, reset counter
                    previous_position = prediction
                    stable_start_time = timestamp

                # Stream Frame Result
                yield json.dumps({
                    'type': 'frame',
                    'timestamp': timestamp,
                    'timestamp_formatted': timestamp_formatted,
                    'frame': current_frame,
                    'prediction': prediction,
                    'confidence': confidence
                }) + '\n'
                
            current_frame += 1
            
    except Exception as e:
        yield json.dumps({'type': 'error', 'message': str(e)}) + '\n'
    finally:
        cap.release()
        if cleanup_dir and os.path.exists(cleanup_dir):
            shutil.rmtree(cleanup_dir)

# --- CHAT ENDPOINTS ---

@app.route('/api/chat/users', methods=['GET'])
def get_chat_users():
    current_user = request.args.get('current_user') # Keep for identifying history later
    conn = get_db_connection()
    try:
        # Show all nurses/users, only exclude those with 'admin' role
        # Also dynamically update who is online based on last_seen (within 60 seconds)
        cursor = conn.execute("SELECT username, name, role, photo_url, phone, nurse_id, joined_date, address, is_online, last_seen FROM nurses WHERE role != 'admin'")
        raw_users = [dict(row) for row in cursor.fetchall()]
        
        users = []
        now = datetime.now()
        for user in raw_users:
            is_online = user['is_online'] == 1
            if is_online and user['last_seen']:
                try:
                    last_seen = datetime.fromisoformat(user['last_seen'])
                    if (now - last_seen).total_seconds() > 60:
                        is_online = False
                        # Update DB to persist this offline status
                        try:
                            conn_update = get_db_connection()
                            conn_update.execute("UPDATE nurses SET is_online = 0 WHERE username = ?", (user['username'],))
                            conn_update.commit()
                            conn_update.close()
                        except:
                            pass
                except:
                    pass
            
            user['is_online'] = 1 if is_online else 0
            users.append(user)
        
        # Optionally add last message info for each user
        for user in users:
            last_msg_cursor = conn.execute('''
                SELECT text, timestamp FROM messages 
                WHERE (sender_username = ? AND recipient_username = ?)
                OR (sender_username = ? AND recipient_username = ?)
                ORDER BY id DESC LIMIT 1
            ''', (current_user, user['username'], user['username'], current_user))
            last_msg = last_msg_cursor.fetchone()
            if last_msg:
                user['last_message'] = last_msg['text']
                user['last_timestamp'] = last_msg['timestamp']
            else:
                user['last_message'] = None
                user['last_timestamp'] = None
            
            # Add unread counts
            unread_cursor = conn.execute('''
                SELECT COUNT(*) FROM messages 
                WHERE sender_username = ? AND recipient_username = ? AND is_read = 0
            ''', (user['username'], current_user))
            user['unread_count'] = unread_cursor.fetchone()[0]
                
        return jsonify(users)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/api/chat/history/<recipient>', methods=['GET'])
def get_chat_history(recipient):
    sender = request.args.get('sender')
    conn = get_db_connection()
    try:
        cursor = conn.execute('''
            SELECT * FROM messages 
            WHERE (sender_username = ? AND recipient_username = ?)
            OR (sender_username = ? AND recipient_username = ?)
            ORDER BY id ASC
        ''', (sender, recipient, recipient, sender))
        history = [dict(row) for row in cursor.fetchall()]
        
        # Mark messages as read
        conn.execute('''
            UPDATE messages SET is_read = 1 
            WHERE sender_username = ? AND recipient_username = ?
        ''', (recipient, sender))
        conn.commit()
        
        return jsonify(history)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/api/chat/send', methods=['POST'])
def send_message():
    data = request.get_json()
    conn = get_db_connection()
    try:
        conn.execute('''
            INSERT INTO messages (sender_username, recipient_username, text, timestamp, type, media_url)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            data['sender'], 
            data['recipient'], 
            data['text'], 
            datetime.now().isoformat(),
            data.get('type', 'text'),
            data.get('media_url')
        ))
        conn.commit()
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/api/chat/upload_media', methods=['POST'])
def upload_chat_media():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400
    
    # Generate unique filename
    ext = os.path.splitext(file.filename)[1]
    filename = f"media_{int(datetime.now().timestamp())}_{os.urandom(4).hex()}{ext}"
    file_path = os.path.join(CHAT_AUDIO_FOLDER, filename)
    file.save(file_path)
    
    # Return relative URL (reusing the existing serve_chat_audio route which serves from CHAT_AUDIO_FOLDER)
    # Ideally we should rename CHAT_AUDIO_FOLDER to CHAT_MEDIA_FOLDER but for minimal disruption we keep the variable name
    # and just serve it via the same path or a alias path.
    return jsonify({"media_url": f"/uploads/chat_audio/{filename}"})

# Maintain backward compatibility while supporting new media
@app.route('/api/chat/upload_audio', methods=['POST'])
def upload_chat_audio():
    # Reuse the new logic or keep separate if specific audio handling is needed
    return upload_chat_media()

@app.route('/uploads/chat_audio/<filename>')
def serve_chat_media(filename):
    return send_from_directory(CHAT_AUDIO_FOLDER, filename)

# --- DUTY BROADCAST ENDPOINTS ---
duty_broadcasts = []

@app.route('/api/duty/broadcast', methods=['POST'])
def duty_broadcast():
    try:
        data = request.get_json()
        if not data or 'nurseName' not in data:
            return jsonify({"error": "No nurse name provided"}), 400
            
        broadcast_id = f"duty_{int(time.time() * 1000)}"
        new_broadcast = {
            'id': broadcast_id,
            'nurseName': data['nurseName'],
            'timestamp': time.time(),
            'message': f"{data['nurseName']} is now On Duty 👋"
        }
        
        # Keep only last 20 broadcasts and remove those older than 30 seconds
        global duty_broadcasts
        current_time = time.time()
        duty_broadcasts = [b for b in duty_broadcasts if (current_time - b['timestamp']) < 30]
        duty_broadcasts.append(new_broadcast)
        if len(duty_broadcasts) > 20:
            duty_broadcasts.pop(0)
            
        return jsonify({"status": "success", "broadcast_id": broadcast_id})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/duty/broadcasts', methods=['GET'])
def get_duty_broadcasts():
    try:
        current_time = time.time()
        # Return broadcasts from the last 10 seconds to account for polling delays
        recent = [b for b in duty_broadcasts if (current_time - b['timestamp']) < 10]
        return jsonify(recent)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- PATIENT MANAGEMENT ENDPOINTS ---

@app.route('/api/patients', methods=['GET'])
def get_patients():
    conn = get_db_connection()
    try:
        cursor = conn.execute('SELECT * FROM patients ORDER BY name ASC')
        patients = [dict(row) for row in cursor.fetchall()]
        return jsonify(patients)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/api/patients', methods=['POST'])
def save_patient_api():
    data = request.get_json()
    if not data or 'id' not in data or 'name' not in data:
        return jsonify({"error": "Missing required fields"}), 400
        
    conn = get_db_connection()
    try:
        # Using REPLACE to handle both insert and update
        conn.execute('''REPLACE INTO patients (id, name, age, room, condition, timestamp)
                      VALUES (?, ?, ?, ?, ?, ?)''',
                      (data['id'], data['name'], data.get('age'), 
                       data.get('room'), data.get('condition'), 
                       datetime.now().isoformat()))
        conn.commit()
        return jsonify({"status": "success", "id": data['id']})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/api/patients/<id>', methods=['DELETE'])
def delete_patient(id):
    conn = get_db_connection()
    try:
        conn.execute('DELETE FROM patients WHERE id = ?', (id,))
        conn.commit()
        return jsonify({"status": "success", "message": "Patient deleted"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

@app.route('/patients/manage')
def manage_patients_ui():
    template = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Patient Management | ThermalVision AI</title>
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --primary: #2563eb;
                --primary-hover: #1d4ed8;
                --bg: #f8fafc;
                --text: #1e293b;
                --text-muted: #64748b;
                --card-bg: #ffffff;
                --border: #e2e8f0;
                --success: #22c55e;
                --error: #ef4444;
            }
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { font-family: 'Inter', sans-serif; background-color: var(--bg); color: var(--text); padding: 2rem; }
            .container { max-width: 1000px; margin: 0 auto; }
            header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }
            h1 { font-size: 1.8rem; font-weight: 700; color: #0f172a; }
            button { cursor: pointer; border: none; font-family: inherit; transition: all 0.2s; background: transparent; }
            .btn-primary { background: var(--primary); color: white; padding: 0.75rem 1.5rem; border-radius: 0.5rem; font-weight: 600; }
            .btn-primary:hover { background: var(--primary-hover); }
            
            .card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 1rem; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); overflow: hidden; }
            table { width: 100%; border-collapse: collapse; }
            th { text-align: left; padding: 1rem; background: #f1f5f9; font-weight: 600; color: var(--text-muted); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; }
            td { padding: 1rem; border-top: 1px solid var(--border); vertical-align: middle; }
            .badge { padding: 0.25rem 0.5rem; border-radius: 0.25rem; font-size: 0.75rem; font-weight: 600; }
            .badge-age { background: #e0f2fe; color: #0369a1; }
            
            .actions { display: flex; gap: 0.5rem; }
            .btn-icon { padding: 0.5rem 0.75rem; border-radius: 0.375rem; background: #f1f5f9; color: var(--text-muted); font-size: 0.875rem; }
            .btn-icon:hover { background: #e2e8f0; color: var(--text); }
            .btn-delete:hover { background: #fee2e2 !important; color: var(--error) !important; }
            
            .modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); backdrop-filter: blur(4px); display: none; justify-content: center; align-items: center; z-index: 100; }
            .modal { background: white; padding: 2rem; border-radius: 1rem; width: 100%; max-width: 500px; box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1); }
            .form-group { margin-bottom: 1.25rem; }
            label { display: block; font-size: 0.875rem; font-weight: 500; margin-bottom: 0.5rem; }
            input, textarea { width: 100%; padding: 0.75rem; border: 1px solid var(--border); border-radius: 0.5rem; font-family: inherit; font-size: 0.95rem; }
            input:focus, textarea:focus { outline: none; border-color: var(--primary); box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1); }
            .modal-actions { display: flex; justify-content: flex-end; gap: 1rem; margin-top: 1.5rem; }
            .btn-text { color: var(--text-muted); font-weight: 500; }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <div>
                    <h1>Patient Management</h1>
                    <p style="color: var(--text-muted); margin-top: 0.25rem;">Add, edit, and keep track of all patients centrally.</p>
                </div>
                <button class="btn-primary" onclick="showModal()">+ Add Patient</button>
            </header>

            <div class="card">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Name</th>
                            <th>Age</th>
                            <th>Room</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody id="patientList"></tbody>
                </table>
            </div>
        </div>

        <div id="modalOverlay" class="modal-overlay">
            <div class="modal">
                <h2 id="modalTitle" style="margin-bottom: 1.5rem; font-size: 1.5rem;">Add Patient</h2>
                <form id="patientForm">
                    <div class="form-group">
                        <label>Patient ID</label>
                        <input type="text" id="p_id" required placeholder="P-001">
                    </div>
                    <div class="form-group">
                        <label>Full Name</label>
                        <input type="text" id="p_name" required placeholder="John Smith">
                    </div>
                    <div style="display: flex; gap: 1rem;">
                        <div class="form-group" style="flex: 1;">
                            <label>Age</label>
                            <input type="number" id="p_age" required>
                        </div>
                        <div class="form-group" style="flex: 1;">
                            <label>Room/Bed</label>
                            <input type="text" id="p_room" placeholder="ICU-102">
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Medical Condition</label>
                        <textarea id="p_condition" rows="3" placeholder="Primary diagnosis and critical notes..."></textarea>
                    </div>
                    <div class="modal-actions">
                        <button type="button" class="btn-text" onclick="hideModal()">Cancel</button>
                        <button type="submit" class="btn-primary">Save Changes</button>
                    </div>
                </form>
            </div>
        </div>

        <script>
            let patients = [];

            async function load() {
                const res = await fetch('/api/patients');
                patients = await res.json();
                const list = document.getElementById('patientList');
                list.innerHTML = patients.length ? patients.map(p => `
                    <tr>
                        <td style="font-family: monospace; font-weight: 600; color: var(--primary);">${p.id}</td>
                        <td style="font-weight: 500;">${p.name}</td>
                        <td><span class="badge badge-age">${p.age} Yrs</span></td>
                        <td style="color: var(--text-muted);">${p.room || 'N/A'}</td>
                        <td class="actions">
                            <button class="btn-icon" onclick="edit('${p.id}')">Edit</button>
                            <button class="btn-icon btn-delete" onclick="remove('${p.id}')">Delete</button>
                        </td>
                    </tr>
                `).join('') : '<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 4rem;">No patients in database</td></tr>';
            }

            async function remove(id) {
                if(confirm('Delete patient ' + id + '?')) {
                    await fetch('/api/patients/' + id, { method: 'DELETE' });
                    load();
                }
            }

            function showModal(id = null) {
                document.getElementById('modalOverlay').style.display = 'flex';
                document.getElementById('patientForm').reset();
                if (id) {
                    const p = patients.find(x => x.id === id);
                    document.getElementById('modalTitle').innerText = 'Edit Patient';
                    document.getElementById('p_id').value = p.id;
                    document.getElementById('p_id').readOnly = true;
                    document.getElementById('p_name').value = p.name;
                    document.getElementById('p_age').value = p.age;
                    document.getElementById('p_room').value = p.room || '';
                    document.getElementById('p_condition').value = p.condition || '';
                } else {
                    document.getElementById('modalTitle').innerText = 'Add New Patient';
                    document.getElementById('p_id').readOnly = false;
                }
            }

            function hideModal() { document.getElementById('modalOverlay').style.display = 'none'; }

            function edit(id) { showModal(id); }

            document.getElementById('patientForm').onsubmit = async (e) => {
                e.preventDefault();
                await fetch('/api/patients', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        id: document.getElementById('p_id').value,
                        name: document.getElementById('p_name').value,
                        age: document.getElementById('p_age').value,
                        room: document.getElementById('p_room').value,
                        condition: document.getElementById('p_condition').value
                    })
                });
                hideModal();
                load();
            };

            load();
        </script>
    </body>
    </html>
    """
    return render_template_string(template)

if __name__ == '__main__':
    # Check for CLI arguments
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == 'sync-db':
            sync_database()
        elif command == 'view-db':
            view_database()
        elif command == 'inspect-db':
            inspect_db()
        elif command == 'init-db':
            try:
                init_db()
                print("✅ Database initialized manually.")
            except Exception as e:
                print(f"❌ Error initializing database: {e}")
        elif command == 'help':
            print("Available commands:")
            print("  python app.py           # Start the server (default)")
            print("  python app.py sync-db   # Sync DB from hidden folder to local snapshot")
            print("  python app.py view-db   # View DB contents")
            print("  python app.py inspect-db # Export DB schema to JSON")
            print("  python app.py init-db   # Initialize database tables")
        else:
            print(f"Unknown command: {command}")
            print("Use 'python app.py help' for available commands.")
    else:
        # Default behavior: Start Server
        print("🚀 Starting ThermalVision AI Server...")
        print(f"📁 Model loaded: {model is not None}")
        print(f"🎯 Available classes: {classes}")
        print("🌐 Server running on http://127.0.0.1:5000")
        print("📋 Available endpoints:")
        print("   GET  / - API information")
        print("   POST /predict - Analyze image")
        print("   POST /predict_video - Analyze video (first frame)")
        print("   POST /predict_video_frames - Analyze multiple video frames")
        print("   GET  /health - Health check")
        print("   GET  /api/history - Get history")
        print("   POST /api/patient - Save patient data")
        print("   POST /api/alert - Save alert data")
        print("   DELETE /api/history/<id> - Delete history record")
        print("   DELETE /api/alert/<id> - Delete alert record")
        print("   DELETE /api/history/all - Clear all history/alerts")
        
        app.run(debug=True, host='0.0.0.0', port=5000)

