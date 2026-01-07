import os
import io
import torch
import torch.nn as nn
from torchvision import models
import torchvision.transforms as T
from PIL import Image
import numpy as np
from flask import Flask, request, jsonify
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

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    # Create tables if they don't exist
    conn.execute('''CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY, name TEXT, age INTEGER, room TEXT, condition TEXT, timestamp TEXT
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY, patient_id TEXT, patient_name TEXT, position TEXT, 
        duration TEXT, type TEXT, timestamp TEXT, acknowledged_by TEXT, status TEXT,
        analysis_result TEXT
    )''')
    
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
        conn = get_db_connection()
        cursor = conn.execute('''
            SELECT a.*, a.patient_id as patientId, a.patient_name as patientName 
            FROM alerts a 
            ORDER BY a.timestamp DESC
        ''')
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