// ThermalVision AI - Complete Fixed Version with Enhanced Security and Authentication
class ThermalVisionApp {
    constructor() {
        this.currentUser = null;
        this.currentPatient = null;
        this.selectedFile = null;
        this.API_BASE = window.location.origin.includes('localhost') ? 'http://localhost:5000' : window.location.origin;

        this.USER_ROLES = {
            ADMIN: 'admin',
            USER: 'user'
        };

        this.DEFAULT_USERS = {
            'admin': { password: 'admin123', role: 'admin', name: 'System Administrator' },
            'nurse': { password: 'nurse123', role: 'user', name: 'Nurse User' }
        };

        this.DB_KEYS = {
            PATIENTS: 'thermalvision_patients',
            ALERTS: 'thermalvision_alerts',
            HISTORY: 'thermalvision_history'
        };

        // ALERT QUEUE SYSTEM
        this.alertQueue = [];
        this.isProcessingAlert = false;
        this.currentAnalysisData = null;

        // Track authentication state
        this.isAuthenticated = false;
    }

    // Initialize Application
    async init() {
        console.log('🚀 Initializing ThermalVision AI System...');

        try {
            this.initDatabase();
            this.setupEventListeners();
            await this.checkAuthStatus();
            await this.testBackendConnection();

            console.log('✅ ThermalVision AI System ready!');
        } catch (error) {
            console.error('❌ Initialization failed:', error);
            this.showNotification('System initialization failed. Please refresh.', 'error');
        }
    }

    // Database Management
    initDatabase() {
        if (!localStorage.getItem(this.DB_KEYS.PATIENTS)) {
            localStorage.setItem(this.DB_KEYS.PATIENTS, JSON.stringify([]));
        }
        if (!localStorage.getItem(this.DB_KEYS.ALERTS)) {
            localStorage.setItem(this.DB_KEYS.ALERTS, JSON.stringify([]));
        }
        if (!localStorage.getItem(this.DB_KEYS.HISTORY)) {
            localStorage.setItem(this.DB_KEYS.HISTORY, JSON.stringify([]));
        }
    }

    getDatabase(key) {
        try {
            return JSON.parse(localStorage.getItem(key)) || [];
        } catch (error) {
            console.error('Database error:', error);
            return [];
        }
    }

    saveToDatabase(key, data) {
        try {
            localStorage.setItem(key, JSON.stringify(data));
            return true;
        } catch (error) {
            console.error('Save error:', error);
            return false;
        }
    }

    // Event Listeners Setup
    setupEventListeners() {
        // Login System
        const loginForm = document.getElementById('loginForm');
        if (loginForm) {
            loginForm.addEventListener('submit', (e) => this.handleLogin(e));
        }

        // Logout
        const logoutBtn = document.getElementById('logoutBtn');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', () => this.logout());
        }

        // Navigation - SECURED
        const navTabs = document.querySelectorAll('.nav-tab');
        navTabs.forEach(tab => {
            tab.addEventListener('click', () => {
                if (!this.isAuthenticated) {
                    this.showNotification('Please login first to access this page', 'error');
                    this.showPage('login-page');
                    return;
                }

                const targetPage = tab.getAttribute('data-page');
                this.showPage(targetPage + '-page');

                // Update active tab
                navTabs.forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
            });
        });

        // File Upload
        const uploadArea = document.getElementById('uploadArea');
        const fileInput = document.getElementById('fileInput');
        const predictBtn = document.getElementById('predictBtn');

        if (uploadArea) {
            uploadArea.addEventListener('click', () => {
                if (!this.isAuthenticated) {
                    this.showNotification('Please login first to upload files', 'error');
                    this.showPage('login-page');
                    return;
                }
                fileInput.click();
            });
            this.setupDragAndDrop(uploadArea);
        }

        if (fileInput) {
            fileInput.addEventListener('change', (e) => this.handleFileSelect(e));
        }

        if (predictBtn) {
            predictBtn.addEventListener('click', () => this.handlePrediction());
        }

        // Patient Modal
        this.setupPatientModal();

        // History System
        this.setupHistorySystem();

        // Alert System
        this.setupAlertSystem();

        // Nurse Management
        this.setupNurseManagement();

        // Doctor Management
        this.setupDoctorManagement();

        // Patient Management
        this.setupPatientManagement();

        // Prevent access to pages via URL manipulation
        this.setupRouteSecurity();
    }





    // Route Security - Prevent direct URL access
    setupRouteSecurity() {
        // Override navigation to check authentication
        const originalPushState = history.pushState;
        const originalReplaceState = history.replaceState;

        history.pushState = function (state, title, url) {
            originalPushState.apply(this, arguments);
            window.dispatchEvent(new Event('popstate'));
        };

        history.replaceState = function (state, title, url) {
            originalReplaceState.apply(this, arguments);
            window.dispatchEvent(new Event('popstate'));
        };

        window.addEventListener('popstate', () => {
            this.checkAuthStatus();
        });

        // Prevent back button from going to secured pages
        window.addEventListener('beforeunload', () => {
            if (!this.isAuthenticated) {
                localStorage.removeItem('currentUser');
            }
        });
    }

    // Authentication System - ENHANCED SECURITY
    async checkAuthStatus() {
        const savedUser = localStorage.getItem('currentUser');
        if (savedUser) {
            try {
                this.currentUser = JSON.parse(savedUser);
                this.isAuthenticated = true;
                this.updateUIForUserRole();
                this.showPage('analysis-page');
                console.log('✅ User authenticated:', this.currentUser.username);
            } catch (error) {
                console.error('❌ Auth token corrupted:', error);
                this.logout();
            }
        } else {
            this.isAuthenticated = false;
            this.showPage('login-page');
            this.hideAllPagesExceptLogin();
        }
    }

    // Hide all pages except login when not authenticated
    hideAllPagesExceptLogin() {
        const pages = document.querySelectorAll('.page');
        pages.forEach(page => {
            if (page.id !== 'login-page') {
                page.classList.remove('active');
            }
        });

        // Hide navigation tabs
        const navTabs = document.querySelectorAll('.nav-tab');
        navTabs.forEach(tab => {
            tab.style.display = 'none';
        });

        // Hide logout button
        const logoutBtn = document.getElementById('logoutBtn');
        if (logoutBtn) {
            logoutBtn.style.display = 'none';
        }
    }

    async handleLogin(e) {
        e.preventDefault();

        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const role = document.getElementById('role').value;

        if (this.DEFAULT_USERS[username] &&
            this.DEFAULT_USERS[username].password === password &&
            this.DEFAULT_USERS[username].role === role) {

            this.currentUser = {
                username: username,
                role: role,
                name: this.DEFAULT_USERS[username].name
            };

            localStorage.setItem('currentUser', JSON.stringify(this.currentUser));
            this.isAuthenticated = true;

            // Enable audio after user interaction (login)
            this.enableAudio();

            this.showNotification('Login successful!', 'success');
            setTimeout(() => {
                this.showPage('analysis-page');
                this.updateUIForUserRole();
                this.showNavigationTabs();
            }, 1000);
        } else {
            this.showNotification('Invalid credentials. Please try again.', 'error');
        }
    }

    // Show navigation tabs after successful login
    showNavigationTabs() {
        const navTabs = document.querySelectorAll('.nav-tab');
        navTabs.forEach(tab => {
            tab.style.display = 'flex';
        });
    }

    enableAudio() {
        // This enables audio after user interaction
        const alertSound = document.getElementById('alertSound');
        if (alertSound) {
            // Play and immediately pause to "unlock" audio
            alertSound.play().then(() => {
                alertSound.pause();
                alertSound.currentTime = 0;
                console.log('🔊 Audio enabled after user interaction');
            }).catch(error => {
                console.log('🔇 Audio enable failed:', error);
            });
        }
    }

    updateUIForUserRole() {
        if (!this.currentUser) return;

        const adminOnlyElements = document.querySelectorAll('.admin-only');
        const logoutBtn = document.getElementById('logoutBtn');

        if (this.currentUser.role === this.USER_ROLES.ADMIN) {
            adminOnlyElements.forEach(el => el.style.display = 'block');
        } else {
            adminOnlyElements.forEach(el => el.style.display = 'none');
        }

        if (logoutBtn) {
            logoutBtn.style.display = 'block';
        }
    }

    logout() {
        this.currentUser = null;
        this.currentPatient = null;
        this.isAuthenticated = false;
        localStorage.removeItem('currentUser');

        this.showPage('login-page');
        this.hideAllPagesExceptLogin();
        this.showNotification('Logged out successfully', 'success');

        // Reset file input
        this.resetFileInput();
    }

    // Navigation - SECURED
    showPage(pageId) {
        // Security check - only allow login page if not authenticated
        if (!this.isAuthenticated && pageId !== 'login-page') {
            console.warn('🚫 Unauthorized access attempt to:', pageId);
            this.showNotification('Please login to access this page', 'error');
            this.showPage('login-page');
            return;
        }

        const pages = document.querySelectorAll('.page');
        pages.forEach(page => page.classList.remove('active'));

        const targetPage = document.getElementById(pageId);
        if (targetPage) {
            targetPage.classList.add('active');
        }

        // Load page-specific data only if authenticated
        if (this.isAuthenticated) {
            if (pageId === 'history-page') {
                this.loadHistoryData();
            }
            if (pageId === 'nurses-page') {
                this.loadNurseData();
            }
            if (pageId === 'doctors-page') {
                this.loadDoctorData();
            }
            if (pageId === 'patients-page') {
                this.loadPatientData();
            }
        }
    }

    switchTab(tabName) {
        const pageId = tabName + '-page';
        this.showPage(pageId);

        // Update nav tabs
        const navTabs = document.querySelectorAll('.nav-tab');
        navTabs.forEach(tab => {
            if (tab.getAttribute('data-page') === tabName) {
                tab.classList.add('active');
            } else {
                tab.classList.remove('active');
            }
        });
    }

    // File Upload System - SECURED
    setupDragAndDrop(uploadArea) {
        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            if (!this.isAuthenticated) {
                this.showNotification('Please login first to upload files', 'error');
                return;
            }
            uploadArea.style.backgroundColor = 'rgba(26, 42, 108, 0.2)';
            uploadArea.style.borderColor = '#b21f1f';
        });

        uploadArea.addEventListener('dragleave', (e) => {
            e.preventDefault();
            uploadArea.style.backgroundColor = 'rgba(26, 42, 108, 0.05)';
            uploadArea.style.borderColor = '#1a2a6c';
        });

        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            if (!this.isAuthenticated) {
                this.showNotification('Please login first to upload files', 'error');
                this.showPage('login-page');
                return;
            }

            uploadArea.style.backgroundColor = 'rgba(26, 42, 108, 0.05)';
            uploadArea.style.borderColor = '#1a2a6c';

            if (e.dataTransfer.files.length > 0) {
                const fileInput = document.getElementById('fileInput');
                fileInput.files = e.dataTransfer.files;
                this.handleFileSelect({ target: fileInput });
            }
        });
    }

    handleFileSelect(e) {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to upload files', 'error');
            this.showPage('login-page');
            return;
        }

        console.log('📁 File selected:', e.target.files[0]);

        if (e.target.files.length > 0) {
            this.selectedFile = e.target.files[0];

            // Validate file type
            if (!this.selectedFile.type.startsWith('video/') && !this.selectedFile.type.startsWith('image/')) {
                this.showNotification('Please select a valid video or image file.', 'error');
                this.resetFileInput();
                return;
            }

            // Check if we already have patient info
            if (this.currentPatient) {
                console.log('✅ Patient info already available, showing preview');
                this.previewSelectedFile();
            } else {
                console.log('📋 No patient info, showing modal');
                // Show patient modal immediately
                this.showPatientModal();
            }
        }
    }

    // Patient Modal System - SECURED
    setupPatientModal() {
        const cancelPatientBtn = document.getElementById('cancelPatientBtn');
        const closeModalBtn = document.querySelector('#patientModal .close');
        const patientForm = document.getElementById('patientForm');

        if (cancelPatientBtn) {
            cancelPatientBtn.addEventListener('click', () => this.closePatientModal());
        }

        if (closeModalBtn) {
            closeModalBtn.addEventListener('click', () => this.closePatientModal());
        }

        const patientModal = document.getElementById('patientModal');
        if (patientModal) {
            patientModal.addEventListener('click', (e) => {
                if (e.target === patientModal) {
                    this.closePatientModal();
                }
            });
        }

        if (patientForm) {
            patientForm.addEventListener('submit', (e) => this.handlePatientFormSubmit(e));
        }
    }

    showPatientModal() {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to add patient information', 'error');
            this.showPage('login-page');
            return;
        }

        const modal = document.getElementById('patientModal');
        const form = document.getElementById('patientForm');

        if (modal && form) {
            form.reset();
            modal.style.display = 'block';
            console.log('📋 Patient modal opened');
        }
    }

    closePatientModal() {
        const modal = document.getElementById('patientModal');
        if (modal) {
            modal.style.display = 'none';
        }
        // Don't reset file input here, just close modal
    }

    handlePatientFormSubmit(e) {
        e.preventDefault();

        if (!this.isAuthenticated) {
            this.showNotification('Session expired. Please login again.', 'error');
            this.showPage('login-page');
            return;
        }

        console.log('✅ Patient form submitted');

        const patientData = {
            id: document.getElementById('patientId').value,
            name: document.getElementById('patientName').value,
            age: document.getElementById('patientAge').value,
            room: document.getElementById('patientRoom').value,
            condition: document.getElementById('patientCondition').value,
            timestamp: new Date().toISOString()
        };

        console.log('📝 Patient data:', patientData);

        // Validate required fields
        if (!patientData.id || !patientData.name || !patientData.age) {
            this.showNotification('Please fill in all required fields (ID, Name, Age).', 'error');
            return;
        }

        // Save patient data
        const patients = this.getDatabase(this.DB_KEYS.PATIENTS);
        const existingPatientIndex = patients.findIndex(p => p.id === patientData.id);

        if (existingPatientIndex !== -1) {
            patients[existingPatientIndex] = { ...patients[existingPatientIndex], ...patientData };
        } else {
            patients.push(patientData);
        }

        if (this.saveToDatabase(this.DB_KEYS.PATIENTS, patients)) {
            this.currentPatient = patientData;

            // Sync with Backend
            if (this.API_BASE) {
                fetch(`${this.API_BASE}/api/patients`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(patientData)
                })
                    .then(res => res.json())
                    .then(data => {
                        console.log('✅ Backend patient sync success:', data);
                        this.showNotification('Patient data synced with cloud', 'success');

                        // If we are on patients page, reload data
                        if (document.getElementById('patients-page').classList.contains('active')) {
                            this.loadPatientData();
                        }
                    })
                    .catch(err => {
                        console.warn('⚠️ Backend sync failed:', err);
                        this.showNotification('Data saved locally (Cloud sync failed)', 'warning');
                    });
            }

            this.closePatientModal();
            this.showNotification('Patient information saved successfully', 'success');

            console.log('👤 Current patient set:', this.currentPatient);
            console.log('📁 Selected file:', this.selectedFile);

            // If we have a file, preview it
            if (this.selectedFile) {
                this.previewSelectedFile();
            }

        } else {
            this.showNotification('Error saving patient information', 'error');
        }
    }

    previewSelectedFile() {
        if (!this.selectedFile) {
            console.error('❌ No file selected for preview');
            return;
        }

        console.log('🖼️ Previewing file:', this.selectedFile.name);
        const objectURL = URL.createObjectURL(this.selectedFile);

        if (this.selectedFile.type.startsWith('video/')) {
            document.getElementById('previewPlayer').src = objectURL;
            document.getElementById('videoPreview').style.display = 'block';
            document.getElementById('imagePreview').style.display = 'none';
            console.log('🎥 Video preview displayed');
        } else {
            document.getElementById('previewImage').src = objectURL;
            document.getElementById('imagePreview').style.display = 'block';
            document.getElementById('videoPreview').style.display = 'none';
            console.log('🖼️ Image preview displayed');
        }

        // Enable predict button
        document.getElementById('predictBtn').disabled = false;

        // Update file info
        const fileInfo = document.querySelector('.file-info');
        if (fileInfo && this.currentPatient) {
            fileInfo.textContent = `Patient: ${this.currentPatient.name} | File: ${this.selectedFile.name}`;
            fileInfo.style.color = '#1a2a6c';
            fileInfo.style.fontWeight = 'bold';
        }
    }

    resetFileInput() {
        const fileInput = document.getElementById('fileInput');
        const predictBtn = document.getElementById('predictBtn');

        if (fileInput) fileInput.value = '';
        if (predictBtn) predictBtn.disabled = true;

        this.currentPatient = null;
        this.selectedFile = null;

        // Reset file info
        const fileInfo = document.querySelector('.file-info');
        if (fileInfo) {
            fileInfo.textContent = 'Drag & drop or click to browse files';
            fileInfo.style.color = '#666';
            fileInfo.style.fontWeight = 'normal';
        }

        // Hide previews and results
        document.getElementById('videoPreview').style.display = 'none';
        document.getElementById('imagePreview').style.display = 'none';
        document.getElementById('resultContainer').style.display = 'none';
        document.getElementById('agentContainer').style.display = 'none';
    }

    // Prediction System - SECURED
    async handlePrediction() {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to perform analysis', 'error');
            this.showPage('login-page');
            return;
        }

        console.log('🎯 Starting prediction process...');
        console.log('👤 Current Patient:', this.currentPatient);
        console.log('📁 Selected File:', this.selectedFile);

        // Debug: Check all conditions
        console.log('🔍 Debug Info:');
        console.log('  - currentPatient exists:', !!this.currentPatient);
        console.log('  - selectedFile exists:', !!this.selectedFile);
        console.log('  - currentPatient details:', this.currentPatient);

        if (!this.currentPatient) {
            console.error('❌ No patient information found');
            this.showNotification('Please complete patient information first', 'error');
            return;
        }

        if (!this.selectedFile) {
            console.error('❌ No file selected');
            this.showNotification('Please select a file first', 'error');
            return;
        }

        console.log('🎯 Prediction starting - Patient:', this.currentPatient.name, 'File:', this.selectedFile.name);

        const isVideo = this.selectedFile.type.startsWith('video/');

        // Show loading
        this.showLoading(true);

        // Clear previous results
        document.getElementById('resultContainer').style.display = 'none';
        document.getElementById('agentContainer').style.display = 'none';
        document.getElementById('successMessage').style.display = 'none';
        document.getElementById('errorContainer').style.display = 'none';

        try {
            const endpoint = isVideo ?
                `${this.API_BASE}/predict_video_frames` : `${this.API_BASE}/predict`;

            console.log('🌐 Sending to endpoint:', endpoint);

            const formData = new FormData();
            formData.append('file', this.selectedFile);

            console.log('📤 Sending file to backend...');
            const response = await fetch(endpoint, {
                method: 'POST',
                body: formData
            });

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(`Server error: ${response.status} - ${errorText}`);
            }

            const data = await response.json();
            console.log('✅ Prediction results received:', data);

            if (data.error) {
                throw new Error(data.error);
            }

            // Process and display results
            this.displayResults(data);
            await this.generatePrimarySuggestion(data);

            // Check for alerts
            if (isVideo && data.frame_predictions) {
                this.checkForStaticPositionAlert(data);
                this.checkStaticPositionAlert(data);
            }

            // Save to history
            this.saveAnalysisToHistory(data);

            document.getElementById('successMessage').style.display = 'flex';
            this.showNotification('Analysis completed successfully!', 'success');

        } catch (error) {
            console.error('❌ Prediction error:', error);
            this.showNotification(`Prediction failed: ${error.message}`, 'error');
            document.getElementById('errorContainer').style.display = 'flex';
            document.getElementById('errorContainer').querySelector('span').textContent = error.message;
        } finally {
            this.showLoading(false);
        }
    }

    displayResults(data) {
        if (!data) {
            this.showNotification('No data received from server', 'error');
            return;
        }

        console.log('📊 Displaying results:', data);
        document.getElementById('resultContainer').style.display = 'block';

        // Update basic prediction info
        document.getElementById('predictionValue').textContent = data.prediction || 'Unknown';

        const confidence = data.confidence ?
            `Confidence: ${(data.confidence * 100).toFixed(1)}%` : 'Confidence: 0%';
        document.getElementById('confidenceValue').textContent = confidence;

        // Handle frame analysis for videos
        if (data.frame_predictions) {
            this.displayFrameAnalysis(data);
        } else {
            document.getElementById('frameAnalysisSection').style.display = 'none';
            document.getElementById('frameAnalysisAlert').className = 'frame-analysis-alert green';
            document.getElementById('frameAlertText').innerHTML = '<i class="fas fa-check-circle"></i> Single image analysis completed';
        }

        // Display probability chart
        this.displayProbabilityChart(data);
    }

    displayFrameAnalysis(data) {
        const framePredictions = data.frame_predictions || [];
        const positionChanges = data.position_changes || [];

        // Show frame analysis section
        document.getElementById('frameAnalysisSection').style.display = 'block';

        // Update frame results
        const frameResults = document.getElementById('frameResults');
        frameResults.innerHTML = '';

        framePredictions.forEach(frame => {
            const changeAtFrame = positionChanges.find(change => change.frame_number === frame.frame_number);
            const frameItem = document.createElement('div');
            frameItem.className = `frame-result-item ${changeAtFrame ? 'movement-frame' : ''}`;

            frameItem.innerHTML = `
                <div class="frame-number">${frame.timestamp_formatted}</div>
                <div class="frame-prediction">${frame.prediction}</div>
                <div class="frame-confidence">${(frame.confidence * 100).toFixed(1)}%</div>
                ${changeAtFrame ? '<div class="frame-change-indicator"><i class="fas fa-exchange-alt"></i></div>' : ''}
            `;

            frameResults.appendChild(frameItem);
        });

        // Set alert based on movement
        const movementAnalysis = data.movement_analysis || {};
        const frameAlert = document.getElementById('frameAnalysisAlert');
        const frameAlertText = document.getElementById('frameAlertText');

        if (movementAnalysis.movement_detected) {
            frameAlert.className = 'frame-analysis-alert green';
            frameAlertText.innerHTML = `<i class="fas fa-running"></i> ${movementAnalysis.summary}`;
        } else {
            frameAlert.className = 'frame-analysis-alert red';
            frameAlertText.innerHTML = `<i class="fas fa-bed"></i> No movement detected`;
        }
    }

    // Add this to displayResults function, after displaying frame analysis:
    displayEnhancedSegmentAnalysis(positionSegments) {
        const segmentAnalysis = document.createElement('div');
        segmentAnalysis.className = 'segment-analysis';
        segmentAnalysis.innerHTML = `
        <h4><i class="fas fa-clock"></i> Position Segment Analysis</h4>
        <div class="segment-results" id="segmentResults"></div>
    `;

        document.querySelector('.result-content').appendChild(segmentAnalysis);

        const segmentResults = document.getElementById('segmentResults');
        positionSegments.forEach(segment => {
            const segmentItem = document.createElement('div');
            segmentItem.className = `segment-item ${segment.duration >= 5 ? 'alert-segment' : ''}`;
            segmentItem.innerHTML = `
            <div class="segment-position">${segment.position}</div>
            <div class="segment-duration">${segment.duration.toFixed(1)}s</div>
            <div class="segment-time">${segment.startTime.toFixed(1)}s - ${(segment.startTime + segment.duration).toFixed(1)}s</div>
            ${segment.duration >= 5 ? '<div class="segment-alert-indicator"><i class="fas fa-bell"></i> Alert</div>' : ''}
        `;
            segmentResults.appendChild(segmentItem);
        });
    }

    displayProbabilityChart(data) {
        const probabilityBars = document.getElementById('probabilityBars');
        if (!probabilityBars) return;

        probabilityBars.innerHTML = '';

        if (data.all_classes && data.probabilities) {
            data.all_classes.forEach(className => {
                const prob = data.probabilities[className] || 0;
                const percentage = (prob * 100).toFixed(1);

                const probabilityItem = document.createElement('div');
                probabilityItem.className = 'probability-item';
                probabilityItem.innerHTML = `
                    <div class="class-label">${className}</div>
                    <div class="probability-bar-container">
                        <div class="probability-bar" style="width: ${percentage}%">${percentage}%</div>
                    </div>
                    <div class="probability-value">${percentage}%</div>
                `;

                probabilityBars.appendChild(probabilityItem);
            });
        }
    }

    // AI Suggestion System - SECURED
    async generatePrimarySuggestion(data) {
        if (!this.isAuthenticated) return;
        if (!data || !data.prediction) return;

        // Clear previous suggestions
        document.getElementById('primarySuggestion').innerHTML = '';
        document.getElementById('agentMessage').innerHTML = '';

        // Show agent section
        document.getElementById('agentContainer').style.display = 'block';

        // Show thinking animation
        document.getElementById('agentThinking').style.display = 'block';

        // Simulate AI processing
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Hide thinking animation
        document.getElementById('agentThinking').style.display = 'none';

        // Generate suggestion based on position
        const position = data.prediction.toLowerCase();
        const confidence = data.confidence || 0;

        let suggestion;
        if (confidence < 0.6) {
            suggestion = {
                title: "Position Verification Required",
                description: `Low confidence detection (${(confidence * 100).toFixed(1)}%). Please verify patient position manually.`,
                icon: "fas fa-exclamation-triangle",
                priority: "HIGH"
            };
        } else if (position.includes('supine')) {
            suggestion = {
                title: "Supine Position Care",
                description: "Check sacrum, heels, and elbows for pressure points. Consider repositioning within 2 hours.",
                icon: "fas fa-bed",
                priority: "CRITICAL"
            };
        } else if (position.includes('left')) {
            suggestion = {
                title: "Left Lateral Care",
                description: "Monitor left shoulder, hip, and ankle. Use pillow support between knees.",
                icon: "fas fa-procedures",
                priority: "CRITICAL"
            };
        } else if (position.includes('right')) {
            suggestion = {
                title: "Right Lateral Care",
                description: "Monitor right shoulder, hip, and ankle. Ensure proper body alignment.",
                icon: "fas fa-procedures",
                priority: "CRITICAL"
            };
        } else {
            suggestion = {
                title: "General Position Assessment",
                description: "Monitor patient position and skin integrity regularly.",
                icon: "fas fa-user-md",
                priority: "MEDIUM"
            };
        }

        // Display suggestion
        document.getElementById('agentMessage').innerHTML =
            `<p><strong>AI Analysis Complete:</strong> Detected <strong>${data.prediction}</strong> position with ${(confidence * 100).toFixed(1)}% confidence.</p>`;

        document.getElementById('primarySuggestion').innerHTML = `
            <div class="suggestion-icon-large">
                <i class="${suggestion.icon}"></i>
            </div>
            <div class="suggestion-title">${suggestion.title}</div>
            <div class="suggestion-description">${suggestion.description}</div>
            <div class="priority-indicator">Priority: ${suggestion.priority}</div>
        `;
    }

    // Alert System - CONTINUOUS SOUND UNTIL ACKNOWLEDGED
    setupAlertSystem() {
        const acknowledgeAlertBtn = document.getElementById('acknowledgeAlert');
        const closeAlertBtn = document.getElementById('closeAlert');

        if (acknowledgeAlertBtn) {
            acknowledgeAlertBtn.addEventListener('click', () => this.handleAlertAcknowledgment());
        }

        if (closeAlertBtn) {
            closeAlertBtn.addEventListener('click', () => this.closeAlertPopup());
        }

        // Initialize audio system
        this.initializeAudio();
    }

    initializeAudio() {
        this.audioContext = null;
        this.isAudioEnabled = false;
        this.alertInterval = null;
        this.isAlertPlaying = false;

        // Try to enable audio immediately
        this.enableAudio();
    }

    enableAudio() {
        const alertSound = document.getElementById('alertSound');
        if (!alertSound) {
            console.log('🔇 No alert sound element found');
            return;
        }

        // Set audio properties
        alertSound.volume = 0.7;
        alertSound.preload = 'auto';

        // Try to play and immediately pause to unlock audio
        const playPromise = alertSound.play();

        if (playPromise !== undefined) {
            playPromise.then(() => {
                console.log('🔊 Audio enabled successfully');
                alertSound.pause();
                alertSound.currentTime = 0;
                this.isAudioEnabled = true;
            }).catch(error => {
                console.log('🔇 Audio auto-enable failed, will enable on user interaction:', error);
                this.isAudioEnabled = false;

                // Add click event to enable audio on next user interaction
                document.addEventListener('click', () => {
                    if (!this.isAudioEnabled) {
                        this.forceEnableAudio();
                    }
                }, { once: true });
            });
        }
    }

    forceEnableAudio() {
        const alertSound = document.getElementById('alertSound');
        if (alertSound) {
            alertSound.play().then(() => {
                console.log('🔊 Audio forcefully enabled');
                alertSound.pause();
                alertSound.currentTime = 0;
                this.isAudioEnabled = true;
            }).catch(error => {
                console.log('🔇 Force enable also failed:', error);
                this.isAudioEnabled = false;
            });
        }
    }

    checkForStaticPositionAlert(data) {
        if (!this.isAuthenticated) return;

        const framePredictions = data.frame_predictions || [];
        if (framePredictions.length < 5) return;

        const firstPosition = framePredictions[0].prediction;
        const allSamePosition = framePredictions.every(frame => frame.prediction === firstPosition);

        if (allSamePosition) {
            const duration = data.video_metadata?.duration_seconds || 0;
            this.showCriticalAlert(firstPosition, duration);
        }
    }

    showCriticalAlert(position, duration) {
        if (!this.isAuthenticated) return;

        document.getElementById('alertDetails').textContent =
            `Patient has maintained ${position} position for ${Math.round(duration)} seconds without movement.`;
        document.getElementById('alertPatientName').textContent = this.currentPatient?.name || 'Unknown';
        document.getElementById('alertPosition').textContent = position;
        document.getElementById('alertDuration').textContent = `${Math.round(duration)} seconds`;

        document.getElementById('alertPopup').style.display = 'block';

        // Start continuous alert until acknowledged
        this.startContinuousAlert();
    }

    startContinuousAlert() {
        if (this.isAlertPlaying) {
            return; // Already playing
        }

        this.isAlertPlaying = true;
        console.log('🔊 Starting continuous alert...');

        // Play alert immediately
        this.playAlertWithFallbacks();

        // Set up interval to repeat alert every 5 seconds
        this.alertInterval = setInterval(() => {
            if (this.isAlertPlaying) {
                console.log('🔊 Repeating alert...');
                this.playAlertWithFallbacks();
            }
        }, 5000);
    }

    stopContinuousAlert() {
        if (this.alertInterval) {
            clearInterval(this.alertInterval);
            this.alertInterval = null;
        }
        this.isAlertPlaying = false;
        console.log('🔇 Continuous alert stopped');

        // Stop any playing audio
        this.stopAllAudio();
    }

    stopAllAudio() {
        // Stop HTML5 audio
        const alertSound = document.getElementById('alertSound');
        if (alertSound) {
            alertSound.pause();
            alertSound.currentTime = 0;
        }

        // Stop Web Audio if active
        if (this.audioContext) {
            // We'll handle this in the individual play methods
        }
    }



    playAlertWithFallbacks() {
        // Try HTML5 audio first
        if (this.isAudioEnabled) {
            this.playHTML5Alert();
        } else {
            // If HTML5 audio is not enabled, try Web Audio API
            this.playWebAudioAlert();
        }
    }

    playHTML5Alert() {
        const alertSound = document.getElementById('alertSound');
        if (!alertSound) {
            this.playWebAudioAlert();
            return;
        }

        console.log('🔊 Attempting HTML5 audio playback...');

        // Reset and play
        alertSound.currentTime = 0;
        alertSound.volume = 0.7;

        const playPromise = alertSound.play();

        if (playPromise !== undefined) {
            playPromise.then(() => {
                console.log('🔊 HTML5 alert sound playing successfully');
            }).catch(error => {
                console.log('🔇 HTML5 audio play failed, trying Web Audio:', error);
                this.playWebAudioAlert();
            });
        }
    }

    playWebAudioAlert() {
        try {
            // Create audio context if it doesn't exist
            if (!this.audioContext) {
                this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            }

            console.log('🎵 Creating Web Audio alert...');

            // Create oscillator for beep sound
            const oscillator = this.audioContext.createOscillator();
            const gainNode = this.audioContext.createGain();

            oscillator.connect(gainNode);
            gainNode.connect(this.audioContext.destination);

            // Configure the beep - more urgent pattern
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(800, this.audioContext.currentTime);

            // Create a more urgent beep pattern (3 quick beeps)
            gainNode.gain.setValueAtTime(0, this.audioContext.currentTime);
            gainNode.gain.linearRampToValueAtTime(0.4, this.audioContext.currentTime + 0.1);
            gainNode.gain.linearRampToValueAtTime(0, this.audioContext.currentTime + 0.2);

            // Second beep
            gainNode.gain.setValueAtTime(0, this.audioContext.currentTime + 0.3);
            gainNode.gain.linearRampToValueAtTime(0.4, this.audioContext.currentTime + 0.4);
            gainNode.gain.linearRampToValueAtTime(0, this.audioContext.currentTime + 0.5);

            // Third beep
            gainNode.gain.setValueAtTime(0, this.audioContext.currentTime + 0.6);
            gainNode.gain.linearRampToValueAtTime(0.4, this.audioContext.currentTime + 0.7);
            gainNode.gain.linearRampToValueAtTime(0, this.audioContext.currentTime + 0.8);

            oscillator.start();

            // Stop oscillator after the pattern completes
            setTimeout(() => {
                oscillator.stop();
                console.log('🎵 Web Audio alert completed');
            }, 1000);

        } catch (error) {
            console.log('🔇 Web Audio also failed, using visual only:', error);
            this.showEnhancedVisualAlert();
        }
    }

    showEnhancedVisualAlert() {
        console.log('🚨 Using enhanced visual alert');

        const alertPopup = document.getElementById('alertPopup');
        if (!alertPopup) return;

        // More prominent visual effects that pulse continuously
        let flashCount = 0;
        const maxFlashes = 999; // Essentially infinite

        // Clear any existing interval
        if (this.visualAlertInterval) {
            clearInterval(this.visualAlertInterval);
        }

        this.visualAlertInterval = setInterval(() => {
            if (flashCount % 2 === 0) {
                // Blue flash (matching theme)
                alertPopup.style.boxShadow = '0 0 40px #1e88e5, 0 0 80px rgba(30, 136, 229, 0.5)';
                alertPopup.style.border = '3px solid #1e88e5';
                document.body.style.backgroundColor = 'rgba(30, 136, 229, 0.1)';
            } else {
                // Normal
                alertPopup.style.boxShadow = '0 25px 50px rgba(0, 0, 0, 0.3)';
                alertPopup.style.border = '1px solid var(--border)';
                document.body.style.backgroundColor = '';
            }

            flashCount++;
        }, 600);

        // Also shake the alert for extra attention
        this.shakeElement(alertPopup);
    }

    stopVisualAlert() {
        if (this.visualAlertInterval) {
            clearInterval(this.visualAlertInterval);
            this.visualAlertInterval = null;
        }

        const alertPopup = document.getElementById('alertPopup');
        if (alertPopup) {
            alertPopup.style.boxShadow = '0 25px 50px rgba(0, 0, 0, 0.3)';
            alertPopup.style.border = '1px solid var(--border)';
            alertPopup.style.animation = '';
        }
        document.body.style.backgroundColor = '';
    }

    shakeElement(element) {
        element.style.animation = 'shake 0.5s ease-in-out';
    }

    handleAlertAcknowledgment() {
        if (!this.isAuthenticated) {
            this.showNotification('Session expired. Please login again.', 'error');
            this.showPage('login-page');
            return;
        }

        // Stop all alerts first
        this.stopContinuousAlert();
        this.stopVisualAlert();

        const alertData = {
            id: this.generateId(),
            patientId: this.currentPatient?.id,
            patientName: this.currentPatient?.name,
            position: document.getElementById('alertPosition').textContent,
            duration: document.getElementById('alertDuration').textContent,
            type: 'critical',
            timestamp: new Date().toISOString(),
            acknowledgedBy: this.currentUser?.name,
            status: 'acknowledged'
        };

        const alerts = this.getDatabase(this.DB_KEYS.ALERTS);
        alerts.push(alertData);
        this.saveToDatabase(this.DB_KEYS.ALERTS, alerts);

        this.closeAlertPopup();
        this.showNotification('Alert acknowledged and logged', 'success');
        this.loadHistoryData();
    }

    closeAlertPopup() {
        // Stop all alerts before closing
        this.stopContinuousAlert();
        this.stopVisualAlert();

        document.getElementById('alertPopup').style.display = 'none';

        // Reset visual effects
        document.body.style.backgroundColor = '';
    }

    // Test method for alert sound
    testAlertSound() {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to test alerts', 'error');
            return;
        }

        console.log('🔊 Testing continuous alert system...');
        console.log('Audio enabled:', this.isAudioEnabled);

        this.showNotification('Testing continuous alert system...', 'info');

        // Show a test alert that will play continuously
        this.showCriticalAlert('Test Position', 120);
    }

    // History System - FIXED FILTERING & SECURED
    setupHistorySystem() {
        const exportBtn = document.getElementById('exportHistoryBtn');
        const clearBtn = document.getElementById('clearHistoryBtn');
        const searchInput = document.getElementById('historySearch');
        const filters = ['timeFilter', 'alertTypeFilter', 'positionFilter'];

        if (exportBtn) exportBtn.addEventListener('click', () => this.exportHistory());
        if (clearBtn) clearBtn.addEventListener('click', () => this.clearHistory());
        if (searchInput) searchInput.addEventListener('input', () => this.loadHistoryData());

        filters.forEach(filterId => {
            const filter = document.getElementById(filterId);
            if (filter) filter.addEventListener('change', () => this.loadHistoryData());
        });
    }

    async loadHistoryData() {
        if (!this.isAuthenticated) {
            console.warn('🚫 Unauthorized history access attempt');
            return;
        }

        try {
            this.showLoading(true);

            // Fetch from backend
            const [historyRes, alertsRes] = await Promise.all([
                fetch(`${this.API_BASE}/api/history`),
                fetch(`${this.API_BASE}/api/alerts`)
            ]);

            const historyData = await historyRes.json();
            const alertsData = await alertsRes.json();

            const history = Array.isArray(historyData) ? historyData : [];
            const alerts = alertsData.alerts ? alertsData.alerts : [];

            // Combine and sort records
            let allRecords = [...history, ...alerts.map(alert => ({
                ...alert,
                isAlert: true
            }))].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

            // Cache records for view details
            this.cachedRecords = allRecords;

            // Apply filters
            allRecords = this.applyFilters(allRecords);

            this.displayHistoryTable(allRecords);
            this.updateHistoryStats(allRecords);

        } catch (error) {
            console.error('❌ Error loading history:', error);
            this.showNotification('Failed to load history from server', 'error');
        } finally {
            this.showLoading(false);
        }
    }

    applyFilters(records) {
        let filteredRecords = [...records];

        // Search filter
        const searchTerm = document.getElementById('historySearch').value.toLowerCase();
        if (searchTerm) {
            filteredRecords = filteredRecords.filter(record =>
                record.patientName?.toLowerCase().includes(searchTerm) ||
                record.patientId?.toLowerCase().includes(searchTerm) ||
                record.prediction?.toLowerCase().includes(searchTerm) ||
                record.position?.toLowerCase().includes(searchTerm)
            );
        }

        // Time filter
        const timeFilter = document.getElementById('timeFilter').value;
        filteredRecords = this.applyTimeFilter(filteredRecords, timeFilter);

        // Alert type filter
        const alertTypeFilter = document.getElementById('alertTypeFilter').value;
        filteredRecords = this.applyAlertTypeFilter(filteredRecords, alertTypeFilter);

        // Position filter
        const positionFilter = document.getElementById('positionFilter').value;
        filteredRecords = this.applyPositionFilter(filteredRecords, positionFilter);

        return filteredRecords;
    }

    applyTimeFilter(records, timeFilter) {
        const now = new Date();

        switch (timeFilter) {
            case 'today':
                return records.filter(record => {
                    const recordDate = new Date(record.timestamp);
                    return recordDate.toDateString() === now.toDateString();
                });

            case 'week':
                const weekAgo = new Date(now);
                weekAgo.setDate(now.getDate() - 7);
                return records.filter(record => {
                    const recordDate = new Date(record.timestamp);
                    return recordDate >= weekAgo;
                });

            case 'month':
                const monthAgo = new Date(now);
                monthAgo.setMonth(now.getMonth() - 1);
                return records.filter(record => {
                    const recordDate = new Date(record.timestamp);
                    return recordDate >= monthAgo;
                });

            default:
                return records; // 'all' - return all records
        }
    }

    applyAlertTypeFilter(records, alertTypeFilter) {
        switch (alertTypeFilter) {
            case 'critical':
                return records.filter(record => record.type === 'critical' || record.isAlert);

            case 'warning':
                return records.filter(record => !record.isAlert && record.confidence && record.confidence < 0.7);

            default:
                return records; // 'all' - return all records
        }
    }

    applyPositionFilter(records, positionFilter) {
        if (positionFilter === 'all') return records;

        return records.filter(record => {
            const position = record.prediction || record.position;
            if (!position) return false;

            return position.toLowerCase().includes(positionFilter.toLowerCase());
        });
    }

    clearFilters() {
        if (!this.isAuthenticated) return;

        document.getElementById('historySearch').value = '';
        document.getElementById('timeFilter').value = 'all';
        document.getElementById('alertTypeFilter').value = 'all';
        document.getElementById('positionFilter').value = 'all';

        this.loadHistoryData();
        this.showNotification('Filters cleared', 'info');
    }

    displayHistoryTable(records) {
        const tbody = document.getElementById('historyTableBody');
        const noHistoryMessage = document.getElementById('noHistoryMessage');

        if (!tbody) return;

        tbody.innerHTML = '';

        // Update filter results info
        this.updateFilterResultsInfo(records);

        if (records.length === 0) {
            noHistoryMessage.style.display = 'block';
            noHistoryMessage.innerHTML = `
                <i class="fas fa-filter"></i>
                <h3>No Records Found</h3>
                <p>No history records match your current filters.</p>
                <button class="btn btn-primary" onclick="app.clearFilters()">
                    <i class="fas fa-times"></i> Clear Filters
                </button>
            `;
            return;
        }

        noHistoryMessage.style.display = 'none';

        records.forEach(record => {
            const isAlert = record.isAlert;
            const alertType = record.type || (isAlert ? 'critical' : 'info');
            const confidence = record.confidence ? `${(record.confidence * 100).toFixed(1)}%` : 'N/A';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td>
                    <strong>${record.patientName || 'Unknown'}</strong>
                    ${record.patientId ? `<br><small>ID: ${record.patientId}</small>` : ''}
                </td>
                <td>
                    ${record.prediction || record.position || 'Unknown'}
                    ${!isAlert ? `<br><small>Confidence: ${confidence}</small>` : ''}
                </td>
                <td>
                    <span class="alert-badge ${alertType}">
                        ${isAlert ? 'CRITICAL ALERT' : 'ANALYSIS'}
                    </span>
                </td>
                <td>${record.duration ? `${record.duration}s` : 'N/A'}</td>
                <td>${this.formatDateTime(record.timestamp)}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn view" onclick="app.viewRecordDetails('${record.id}')">
                            <i class="fas fa-eye"></i> View
                        </button>
                        ${this.currentUser?.role === this.USER_ROLES.ADMIN ? `
                        <button class="action-btn delete" onclick="app.deleteRecord('${record.id}')">
                            <i class="fas fa-trash"></i> Delete
                        </button>
                        ` : ''}
                    </div>
                </td>
            `;

            tbody.appendChild(row);
        });
    }

    updateFilterResultsInfo(records) {
        // Create or update filter results info
        let filterInfo = document.getElementById('filterResultsInfo');
        if (!filterInfo) {
            filterInfo = document.createElement('div');
            filterInfo.id = 'filterResultsInfo';
            filterInfo.className = 'filter-results';
            document.querySelector('.history-filters').appendChild(filterInfo);
        }

        // Simplified display since we don't have total count easily without another fetch
        // or we could pass total count to this function. 
        // For now, just show the count of displayed records.
        filterInfo.textContent = `Showing ${records.length} records`;
    }

    updateHistoryStats(records) {
        document.getElementById('totalAlerts').textContent = records.length;
        document.getElementById('criticalAlerts').textContent = records.filter(r => r.type === 'critical' || r.isAlert).length;

        // Count unique patients
        const uniquePatients = new Set(records.map(r => r.patientId).filter(id => id));
        document.getElementById('patientsMonitored').textContent = uniquePatients.size;
    }


    checkStaticPositionAlert(data) {
        if (!this.isAuthenticated || !data.frame_predictions) return;

        const framePredictions = data.frame_predictions;
        const fps = data.video_metadata?.fps || 1;
        const alertThreshold = 5; // 5 seconds

        console.log('🔍 Checking static position alerts with 5s intervals...');

        let positionSegments = [];
        let currentSegment = {
            position: null,
            startTime: 0,
            startFrame: 0,
            duration: 0
        };

        // Group frames into position segments
        framePredictions.forEach((frame, index) => {
            const currentTime = frame.timestamp_seconds;
            const currentPosition = frame.prediction;

            if (currentSegment.position === null) {
                // First frame
                currentSegment.position = currentPosition;
                currentSegment.startTime = currentTime;
                currentSegment.startFrame = frame.frame_number;
            } else if (currentSegment.position !== currentPosition) {
                // Position changed - save current segment and start new one
                currentSegment.duration = currentTime - currentSegment.startTime;
                positionSegments.push({ ...currentSegment });

                currentSegment = {
                    position: currentPosition,
                    startTime: currentTime,
                    startFrame: frame.frame_number,
                    duration: 0
                };
            }

            // For last frame, calculate final duration
            if (index === framePredictions.length - 1) {
                currentSegment.duration = currentTime - currentSegment.startTime;
                positionSegments.push({ ...currentSegment });
            }
        });

        console.log('📊 Position segments:', positionSegments);

        // Check for static position alerts (5+ seconds)
        const staticAlerts = positionSegments.filter(segment =>
            segment.duration >= alertThreshold
        );

        console.log('🚨 Static alerts found:', staticAlerts);

        // Trigger alerts for static positions
        staticAlerts.forEach(alert => {
            this.showStaticPositionAlert(alert, data.video_metadata);
        });

        // Store analysis with segment information
        this.saveEnhancedAnalysisToHistory(data, positionSegments, staticAlerts);
    }

    showStaticPositionAlert(alertSegment, videoMetadata) {
        if (!this.isAuthenticated) return;

        console.log(`🚨 Static position alert: ${alertSegment.position} for ${alertSegment.duration.toFixed(1)}s`);

        // Update alert popup with static position information
        document.getElementById('alertDetails').textContent =
            `Patient maintained ${alertSegment.position} position for ${alertSegment.duration.toFixed(1)} seconds without movement.`;
        document.getElementById('alertPatientName').textContent = this.currentPatient?.name || 'Unknown';
        document.getElementById('alertPosition').textContent = alertSegment.position;
        document.getElementById('alertDuration').textContent = `${alertSegment.duration.toFixed(1)} seconds`;

        // Show alert popup
        document.getElementById('alertPopup').style.display = 'block';

        // Start continuous alert
        this.startContinuousAlert();
    }

    // Standard history storage
    saveAnalysisToHistory(data) {
        if (!this.isAuthenticated || !this.currentPatient) return;

        const historyRecord = {
            id: this.generateId(),
            patientId: this.currentPatient.id,
            patientName: this.currentPatient.name,
            prediction: data.prediction,
            confidence: data.confidence,
            probabilities: data.probabilities,
            timestamp: new Date().toISOString(),
            analyzedBy: this.currentUser?.name,
            analysisType: 'standard',
            analysis_result: JSON.stringify(data)
        };

        // Save to Backend API
        if (this.API_BASE) {
            fetch(`${this.API_BASE}/api/history`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(historyRecord)
            })
                .then(res => res.json())
                .then(data => console.log('✅ Backend history response:', data))
                .catch(err => console.warn('⚠️ Backend save failed:', err));
        }

        // Save to Local Storage (Backup)
        const history = this.getDatabase(this.DB_KEYS.HISTORY);
        history.push(historyRecord);
        this.saveToDatabase(this.DB_KEYS.HISTORY, history);

        // Update UI if on history page
        if (document.getElementById('history-page').style.display === 'block') {
            this.loadHistoryData();
        }
    }

    // Enhanced history storage
    saveEnhancedAnalysisToHistory(data, positionSegments, staticAlerts) {
        if (!this.isAuthenticated || !this.currentPatient) return;

        const historyRecord = {
            id: this.generateId(),
            patientId: this.currentPatient.id,
            patientName: this.currentPatient.name,
            prediction: data.prediction,
            confidence: data.confidence,
            duration: data.video_metadata?.duration_seconds,
            timestamp: new Date().toISOString(),
            analyzedBy: this.currentUser?.name,
            // Enhanced data
            positionSegments: positionSegments,
            staticAlerts: staticAlerts,
            totalStaticAlerts: staticAlerts.length,
            alertThreshold: 5, // 5 seconds
            analysisType: 'enhanced_static_detection',
            // Full analysis result for replay
            analysis_result: JSON.stringify(data)
        };

        // Save to Backend API
        if (this.API_BASE) {
            fetch(`${this.API_BASE}/api/history`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(historyRecord)
            })
                .then(res => res.json())
                .then(data => console.log('✅ Backend history response:', data))
                .catch(err => console.warn('⚠️ Backend save failed:', err));
        }

        // Save to Local Storage (Backup)
        const history = this.getDatabase(this.DB_KEYS.HISTORY);
        history.push(historyRecord);
        this.saveToDatabase(this.DB_KEYS.HISTORY, history);

        console.log('💾 Enhanced analysis saved to history');
    }
    // Utility Methods
    generateId() {
        return Date.now().toString(36) + Math.random().toString(36).substr(2);
    }

    formatDateTime(timestamp) {
        const date = new Date(timestamp);
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    }

    showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.innerHTML = `
            <i class="fas fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-circle' : 'info-circle'}"></i>
            <span>${message}</span>
        `;

        document.body.appendChild(notification);

        setTimeout(() => {
            notification.style.animation = 'slideInRight 0.3s ease-out reverse';
            setTimeout(() => {
                if (notification.parentNode) {
                    notification.parentNode.removeChild(notification);
                }
            }, 300);
        }, 5000);
    }

    showLoading(show) {
        document.getElementById('loadingIndicator').style.display = show ? 'block' : 'none';
        document.getElementById('predictBtn').disabled = show;
    }

    exportHistory() {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to export history', 'error');
            return;
        }

        // Use cached records from backend if available, otherwise fallback to empty
        let recordsToExport = this.cachedRecords || [];

        // Apply current filters to get only what the user sees
        recordsToExport = this.applyFilters(recordsToExport);

        if (recordsToExport.length === 0) {
            this.showNotification('No records to export', 'warning');
            return;
        }

        const exportData = {
            exportedAt: new Date().toISOString(),
            filterSettings: {
                search: document.getElementById('historySearch').value,
                time: document.getElementById('timeFilter').value,
                type: document.getElementById('alertTypeFilter').value,
                position: document.getElementById('positionFilter').value
            },
            totalRecords: recordsToExport.length,
            records: recordsToExport.map(record => ({
                id: record.id,
                timestamp: record.timestamp,
                dateTime: new Date(record.timestamp).toLocaleString(),
                patientId: record.patientId || record.patient?.id || 'N/A',
                patientName: record.patientName || record.patient?.name || 'Unknown',
                type: record.isAlert ? 'ALERT' : 'ANALYSIS',
                prediction: record.prediction || record.position,
                confidence: record.confidence,
                duration: record.duration,
                analysis_result: record.analysis_result ? JSON.parse(record.analysis_result) : null
            }))
        };

        const dataStr = JSON.stringify(exportData, null, 2);
        const dataBlob = new Blob([dataStr], { type: 'application/json' });

        const url = URL.createObjectURL(dataBlob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `thermalvision_export_${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);

        this.showNotification(`Successfully exported ${recordsToExport.length} records`, 'success');
    }

    clearHistory() {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to clear history', 'error');
            return;
        }

        if (confirm('Are you sure you want to clear ALL history and alerts? This action cannot be undone.')) {
            // Clear from backend
            if (this.API_BASE) {
                fetch(`${this.API_BASE}/api/history/all`, {
                    method: 'DELETE'
                })
                    .then(res => res.json())
                    .then(data => {
                        console.log('✅ Backend clear response:', data);
                        if (data.status === 'success') {
                            // Clear local storage as well
                            localStorage.setItem(this.DB_KEYS.HISTORY, JSON.stringify([]));
                            localStorage.setItem(this.DB_KEYS.ALERTS, JSON.stringify([]));

                            // Refresh view
                            this.loadHistoryData();
                            this.showNotification('All history and alerts cleared from database', 'success');
                        } else {
                            this.showNotification('Failed to clear history from server', 'error');
                        }
                    })
                    .catch(err => {
                        console.error('⚠️ Backend clear failed:', err);
                        this.showNotification('Error clearing history from server', 'error');
                    });
            } else {
                // Fallback to local only
                localStorage.setItem(this.DB_KEYS.HISTORY, JSON.stringify([]));
                localStorage.setItem(this.DB_KEYS.ALERTS, JSON.stringify([]));
                this.loadHistoryData();
                this.showNotification('Local history cleared', 'success');
            }
        }
    }

    viewRecordDetails(recordId) {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to view details', 'error');
            return;
        }

        const record = this.cachedRecords ? this.cachedRecords.find(r => r.id === recordId) : null;

        if (record) {
            console.log('Viewing record:', record);

            // Prepare data for display
            let resultData = {};

            // If it has full analysis result (alerts often do)
            if (record.analysis_result) {
                try {
                    resultData = typeof record.analysis_result === 'string'
                        ? JSON.parse(record.analysis_result)
                        : record.analysis_result;
                } catch (e) {
                    console.warn('Error parsing analysis result:', e);
                }
            }

            // Merge/Override with top-level fields if needed
            resultData.prediction = record.prediction || record.position || resultData.prediction;
            resultData.confidence = record.confidence || resultData.confidence;

            // Handle probabilities
            if (record.probabilities && !resultData.probabilities) {
                try {
                    resultData.probabilities = typeof record.probabilities === 'string'
                        ? JSON.parse(record.probabilities)
                        : record.probabilities;
                } catch (e) { console.warn('Error parsing probabilities:', e); }
            }

            // Switch to analysis tab
            this.switchTab('analysis');

            // Display results
            this.displayResults(resultData);

            // Scroll to results
            document.getElementById('resultContainer').scrollIntoView({ behavior: 'smooth' });

        } else {
            this.showNotification('Record not found', 'error');
        }
    }

    deleteRecord(recordId) {
        if (!this.isAuthenticated) {
            this.showNotification('Please login first to delete records', 'error');
            return;
        }

        if (confirm('Are you sure you want to delete this record?')) {
            // Determine if it's an alert or history record
            const isAlert = recordId.startsWith('alert_');
            const endpoint = isAlert ? `/api/alert/${recordId}` : `/api/history/${recordId}`;

            // Call Backend API
            if (this.API_BASE) {
                fetch(`${this.API_BASE}${endpoint}`, {
                    method: 'DELETE'
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.status === 'success') {
                            console.log('✅ Record deleted from backend');
                        } else {
                            console.warn('⚠️ Failed to delete from backend:', data.error);
                        }
                    })
                    .catch(err => console.error('❌ Error deleting from backend:', err));
            }

            // Update Local Storage (Frontend)
            let history = this.getDatabase(this.DB_KEYS.HISTORY);
            history = history.filter(r => r.id !== recordId);
            this.saveToDatabase(this.DB_KEYS.HISTORY, history);

            let alerts = this.getDatabase(this.DB_KEYS.ALERTS);
            alerts = alerts.filter(r => r.id !== recordId);
            this.saveToDatabase(this.DB_KEYS.ALERTS, alerts);

            this.loadHistoryData();
            this.showNotification('Record deleted successfully', 'success');
        }
    }

    // Backend connection test
    async testBackendConnection() {
        try {
            const response = await fetch(`${this.API_BASE}/health`);
            const data = await response.json();
            console.log('✅ Backend connection successful:', data);

            const subtitle = document.querySelector('.subtitle');
            if (subtitle) {
                subtitle.innerHTML += ` <span style="color: green;">(Backend Connected)</span>`;
            }
        } catch (error) {
            console.error('❌ Backend connection failed:', error);
            this.showNotification('Cannot connect to backend server. Make sure Flask is running on port 5000.', 'error');

            const subtitle = document.querySelector('.subtitle');
            if (subtitle) {
                subtitle.innerHTML += ` <span style="color: red;">(Backend Not Connected)</span>`;
            }
        }
    }

    // Nurse Management System
    setupNurseManagement() {
        const addNurseBtn = document.getElementById('addNurseBtn');
        if (addNurseBtn) {
            addNurseBtn.addEventListener('click', () => this.addNurse());
        }

        const editNurseForm = document.getElementById('editNurseForm');
        if (editNurseForm) {
            editNurseForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.updateNurse();
            });
        }
    }



    async loadNurseData() {
        if (!this.currentUser || this.currentUser.role !== this.USER_ROLES.ADMIN) {
            this.showNotification('Unauthorized access attempted', 'error');
            this.showPage('analysis-page');
            return;
        }

        try {
            const response = await fetch(`${this.API_BASE}/api/nurses`);
            if (!response.ok) throw new Error('Failed to fetch nurses');

            const nurses = await response.json();
            const tableBody = document.getElementById('nurseTableBody');
            tableBody.innerHTML = '';

            nurses.forEach(nurse => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><img src="${nurse.photo_url}" style="width: 40px; height: 40px; border-radius: 50%; object-fit: cover;"></td>
                    <td>${nurse.name}</td>
                    <td>${nurse.username}</td>
                    <td><span class="badge ${nurse.role === 'admin' ? 'badge-admin' : 'badge-user'}">${nurse.role}</span></td>
                    <td>
                        <button class="btn btn-sm btn-primary" onclick="app.openEditNurseModal('${nurse.username}', '${nurse.name.replace(/'/g, "\\'")}', '${nurse.role}', '${nurse.phone || ''}', '${nurse.nurse_id || ''}', '${nurse.joined_date || ''}', '${nurse.address ? nurse.address.replace(/'/g, "\\'") : ''}')">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-sm btn-danger" onclick="app.deleteNurse('${nurse.username}')">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>
                `;
                tableBody.appendChild(row);
            });
        } catch (error) {
            console.error('Error loading nurses:', error);
            this.showNotification('Error loading nurse data', 'error');
        }
    }

    async addNurse() {
        const name = document.getElementById('newNurseName').value;
        const username = document.getElementById('newNurseUsername').value;
        const password = document.getElementById('newNursePassword').value;
        const role = document.getElementById('newNurseRole').value;
        const phone = document.getElementById('newNursePhone').value;
        const nurse_id = document.getElementById('newNurseID').value;
        const joined_date = document.getElementById('newNurseJoinedDate').value;
        const address = document.getElementById('newNurseAddress').value;

        if (!name || !username || !password) {
            this.showNotification('Please fill all fields', 'error');
            return;
        }

        try {
            const response = await fetch(`${this.API_BASE}/api/nurses`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    name, username, password, role,
                    phone, nurse_id, joined_date, address
                })
            });

            if (!response.ok) throw new Error('Failed to add nurse');

            this.showNotification('Nurse added successfully', 'success');
            document.getElementById('newNurseName').value = '';
            document.getElementById('newNurseUsername').value = '';
            document.getElementById('newNursePassword').value = '';
            document.getElementById('newNursePhone').value = '';
            document.getElementById('newNurseID').value = '';
            document.getElementById('newNurseJoinedDate').value = '';
            document.getElementById('newNurseAddress').value = '';
            this.loadNurseData();
        } catch (error) {
            console.error('Error adding nurse:', error);
            this.showNotification('Error adding nurse', 'error');
        }
    }

    async deleteNurse(username) {
        if (!confirm(`Are you sure you want to delete nurse: ${username}?`)) return;

        try {
            const response = await fetch(`${this.API_BASE}/api/nurses/${username}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error('Failed to delete nurse');

            this.showNotification('Nurse deleted successfully', 'success');
            this.loadNurseData();
        } catch (error) {
            console.error('Error deleting nurse:', error);
            this.showNotification('Error deleting nurse', 'error');
        }
    }

    openEditNurseModal(username, name, role, phone, nurse_id, joined_date, address) {
        document.getElementById('editNurseUsername').value = username;
        document.getElementById('editNurseName').value = name;
        document.getElementById('editNurseRole').value = role;
        document.getElementById('editNursePassword').value = '';
        document.getElementById('editNursePhone').value = phone || '';
        document.getElementById('editNurseID').value = nurse_id || '';
        document.getElementById('editNurseJoinedDate').value = joined_date || '';
        document.getElementById('editNurseAddress').value = address || '';
        document.getElementById('editNurseModal').style.display = 'block';
    }

    closeEditNurseModal() {
        document.getElementById('editNurseModal').style.display = 'none';
        document.getElementById('editNurseForm').reset();
    }

    async updateNurse() {
        const username = document.getElementById('editNurseUsername').value;
        const name = document.getElementById('editNurseName').value;
        const role = document.getElementById('editNurseRole').value;
        const password = document.getElementById('editNursePassword').value;
        const phone = document.getElementById('editNursePhone').value;
        const nurse_id = document.getElementById('editNurseID').value;
        const joined_date = document.getElementById('editNurseJoinedDate').value;
        const address = document.getElementById('editNurseAddress').value;

        if (!name || !role) {
            this.showNotification('Name and role are required', 'error');
            return;
        }

        try {
            const data = {
                name, role, phone,
                nurse_id, joined_date, address
            };
            if (password) data.password = password;

            const response = await fetch(`${this.API_BASE}/api/nurses/${username}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });

            if (!response.ok) throw new Error('Failed to update nurse');

            this.showNotification('Nurse updated successfully', 'success');
            this.closeEditNurseModal();
            this.loadNurseData();
        } catch (error) {
            console.error('Error updating nurse:', error);
            this.showNotification('Error updating nurse', 'error');
        }
    }

    // Doctor Management System
    setupDoctorManagement() {
        const addDoctorBtn = document.getElementById('addDoctorBtn');
        if (addDoctorBtn) {
            addDoctorBtn.addEventListener('click', () => this.addDoctor());
        }

        const editDoctorForm = document.getElementById('editDoctorForm');
        if (editDoctorForm) {
            editDoctorForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.updateDoctor();
            });
        }
    }

    async loadDoctorData() {
        if (!this.currentUser || this.currentUser.role !== this.USER_ROLES.ADMIN) {
            this.showNotification('Unauthorized access attempted', 'error');
            this.showPage('analysis-page');
            return;
        }

        try {
            const response = await fetch(`${this.API_BASE}/api/doctors`);
            if (!response.ok) throw new Error('Failed to fetch doctors');

            const doctors = await response.json();
            const tableBody = document.getElementById('doctorTableBody');
            tableBody.innerHTML = '';

            doctors.forEach(doctor => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${doctor.id}</td>
                    <td>${doctor.name}</td>
                    <td>${doctor.position}</td>
                    <td>${doctor.specialty}</td>
                    <td>${doctor.duty_time}</td>
                    <td>
                        <button class="btn btn-sm btn-primary" onclick="app.openEditDoctorModal('${doctor.id}', '${doctor.name.replace(/'/g, "\\'")}', '${doctor.position.replace(/'/g, "\\'")}', '${doctor.specialty.replace(/'/g, "\\'")}', '${doctor.duty_time || ''}', '${doctor.contact || ''}', '${doctor.joined_date || ''}')">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-sm btn-danger" onclick="app.deleteDoctor('${doctor.id}')">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>
                `;
                tableBody.appendChild(row);
            });
        } catch (error) {
            console.error('Error loading doctors:', error);
            this.showNotification('Error loading doctor data', 'error');
        }
    }

    async addDoctor() {
        const id = document.getElementById('newDoctorID').value;
        const name = document.getElementById('newDoctorName').value;
        const position = document.getElementById('newDoctorPosition').value;
        const specialty = document.getElementById('newDoctorSpecialty').value;
        const duty_time = document.getElementById('newDoctorDutyTime').value;
        const contact = document.getElementById('newDoctorContact').value;
        const joined_date = document.getElementById('newDoctorJoinedDate').value;

        if (!id || !name || !position || !specialty) {
            this.showNotification('Please fill all required fields', 'error');
            return;
        }

        try {
            const response = await fetch(`${this.API_BASE}/api/doctors`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id, name, position, specialty,
                    duty_time, contact, joined_date
                })
            });

            if (!response.ok) throw new Error('Failed to add doctor');

            this.showNotification('Doctor added successfully', 'success');
            document.getElementById('newDoctorID').value = '';
            document.getElementById('newDoctorName').value = '';
            document.getElementById('newDoctorPosition').value = '';
            document.getElementById('newDoctorSpecialty').value = '';
            document.getElementById('newDoctorDutyTime').value = '';
            document.getElementById('newDoctorContact').value = '';
            document.getElementById('newDoctorJoinedDate').value = '';
            this.loadDoctorData();
        } catch (error) {
            console.error('Error adding doctor:', error);
            this.showNotification('Error adding doctor', 'error');
        }
    }

    async deleteDoctor(id) {
        if (!confirm(`Are you sure you want to delete doctor: ${id}?`)) return;

        try {
            const response = await fetch(`${this.API_BASE}/api/doctors/${id}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error('Failed to delete doctor');

            this.showNotification('Doctor deleted successfully', 'success');
            this.loadDoctorData();
        } catch (error) {
            console.error('Error deleting doctor:', error);
            this.showNotification('Error deleting doctor', 'error');
        }
    }

    openEditDoctorModal(id, name, position, specialty, duty_time, contact, joined_date) {
        document.getElementById('editDoctorID').value = id;
        document.getElementById('editDoctorName').value = name;
        document.getElementById('editDoctorPosition').value = position;
        document.getElementById('editDoctorSpecialty').value = specialty;
        document.getElementById('editDoctorDutyTime').value = duty_time || '';
        document.getElementById('editDoctorContact').value = contact || '';
        document.getElementById('editDoctorJoinedDate').value = joined_date || '';
        document.getElementById('editDoctorModal').style.display = 'block';
    }

    closeEditDoctorModal() {
        document.getElementById('editDoctorModal').style.display = 'none';
        document.getElementById('editDoctorForm').reset();
    }

    async updateDoctor() {
        const id = document.getElementById('editDoctorID').value;
        const name = document.getElementById('editDoctorName').value;
        const position = document.getElementById('editDoctorPosition').value;
        const specialty = document.getElementById('editDoctorSpecialty').value;
        const duty_time = document.getElementById('editDoctorDutyTime').value;
        const contact = document.getElementById('editDoctorContact').value;
        const joined_date = document.getElementById('editDoctorJoinedDate').value;

        if (!name || !position || !specialty) {
            this.showNotification('Missing required fields', 'error');
            return;
        }

        try {
            const response = await fetch(`${this.API_BASE}/api/doctors/${id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    name, position, specialty,
                    duty_time, contact, joined_date
                })
            });

            if (!response.ok) throw new Error('Failed to update doctor');

            this.showNotification('Doctor updated successfully', 'success');
            this.closeEditDoctorModal();
            this.loadDoctorData();
        } catch (error) {
            console.error('Error updating doctor:', error);
            this.showNotification('Error updating doctor', 'error');
        }
    }

    // Patient Management System
    setupPatientManagement() {
        const openAddPatientBtn = document.getElementById('openAddPatientModalBtn');
        if (openAddPatientBtn) {
            openAddPatientBtn.addEventListener('click', () => {
                this.showPatientModal();
            });
        }

        const patientSearch = document.getElementById('patientSearch');
        if (patientSearch) {
            patientSearch.addEventListener('input', () => this.loadPatientData());
        }
    }

    async loadPatientData() {
        if (!this.isAuthenticated) return;

        try {
            const response = await fetch(`${this.API_BASE}/api/patients`);
            if (!response.ok) throw new Error('Failed to fetch patients');

            let patients = await response.json();

            // Sync local storage with backend data
            this.saveToDatabase(this.DB_KEYS.PATIENTS, patients);
            this.allPatients = patients; // Cache for editing

            const searchTerm = document.getElementById('patientSearch').value.toLowerCase();

            if (searchTerm) {
                patients = patients.filter(p =>
                    p.name.toLowerCase().includes(searchTerm) ||
                    p.id.toLowerCase().includes(searchTerm) ||
                    (p.room && p.room.toLowerCase().includes(searchTerm))
                );
            }

            document.getElementById('totalPatientsCount').textContent = patients.length;

            const tableBody = document.getElementById('patientManagementTableBody');
            tableBody.innerHTML = '';

            if (patients.length === 0) {
                tableBody.innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem;">No patients found.</td></tr>';
                return;
            }

            patients.forEach(p => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><code>${p.id}</code></td>
                    <td><strong>${p.name}</strong></td>
                    <td>${p.age}</td>
                    <td>${p.room || 'N/A'}</td>
                    <td><small>${p.condition || 'N/A'}</small></td>
                    <td>
                        <div class="action-buttons">
                            <button class="action-btn view" onclick="app.editPatient('${p.id}')">
                                <i class="fas fa-edit"></i> Edit
                            </button>
                            <button class="action-btn delete" onclick="app.deletePatient('${p.id}')">
                                <i class="fas fa-trash"></i> Delete
                            </button>
                        </div>
                    </td>
                `;
                tableBody.appendChild(row);
            });
        } catch (error) {
            console.error('Error loading patients:', error);
            this.showNotification('Error loading patient data', 'error');
        }
    }

    editPatient(id) {
        // Use cached data if available, otherwise fallback to local database
        const p = (this.allPatients && this.allPatients.find(x => x.id === id)) ||
            this.getDatabase(this.DB_KEYS.PATIENTS).find(x => x.id === id);

        if (p) {
            this.showPatientModal();

            // Fill form
            document.getElementById('patientId').value = p.id;
            document.getElementById('patientName').value = p.name;
            document.getElementById('patientAge').value = p.age;
            document.getElementById('patientRoom').value = p.room || '';
            document.getElementById('patientCondition').value = p.condition || '';

            // ID should be readonly when editing if desired, but form doesn't handle it yet
            // document.getElementById('patientId').readOnly = true;
        }
    }

    async deletePatient(id) {
        if (!confirm(`Are you sure you want to delete patient ${id}?`)) return;

        try {
            const response = await fetch(`${this.API_BASE}/api/patients/${id}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error('Failed to delete patient');

            this.showNotification('Patient deleted successfully', 'success');

            // Update local storage too
            let patients = this.getDatabase(this.DB_KEYS.PATIENTS);
            patients = patients.filter(p => p.id !== id);
            this.saveToDatabase(this.DB_KEYS.PATIENTS, patients);

            this.loadPatientData();
        } catch (error) {
            console.error('Error deleting patient:', error);
            this.showNotification('Error deleting patient', 'error');
        }
    }
}

// Initialize the application
const app = new ThermalVisionApp();

// Start the application when DOM is loaded
document.addEventListener('DOMContentLoaded', function () {
    app.init();
});

// Global error handler
window.addEventListener('error', function (e) {
    console.error('Global error:', e.error);
    app.showNotification('An unexpected error occurred. Please check the console.', 'error');
});

// Prevent access to pages via direct URL entry
window.addEventListener('load', function () {
    // Check if user is trying to access secured pages without authentication
    const currentPath = window.location.hash;
    if (currentPath && currentPath !== '#login' && !app.isAuthenticated) {
        window.location.hash = '';
        app.showPage('login-page');
    }
});
