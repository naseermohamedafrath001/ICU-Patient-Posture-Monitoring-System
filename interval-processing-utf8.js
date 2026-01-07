// Interval-based Video Processing Module
// This module extends ThermalVisionApp with 5-second interval processing capabilities

(function () {
    console.log('🔄 Loading Interval Processing Module...');

    // Helper to generate a beep using Web Audio API (Fallback)
    let beepInterval = null;

    function playBeep() {
        try {
            const AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;

            const ctx = new AudioContext();
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();

            osc.connect(gain);
            gain.connect(ctx.destination);

            osc.type = 'square';
            osc.frequency.setValueAtTime(440, ctx.currentTime);
            osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.1);

            gain.gain.setValueAtTime(0.5, ctx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.5);

            osc.start();
            osc.stop(ctx.currentTime + 0.5);
            console.log('🔊 Played fallback beep');
        } catch (e) {
            console.error('❌ Fallback beep failed:', e);
        }
    }

    function startBeepLoop() {
        if (beepInterval) clearInterval(beepInterval);
        playBeep(); // Play immediately
        beepInterval = setInterval(playBeep, 2000); // Repeat every 2 seconds
    }

    function stopBeepLoop() {
        if (beepInterval) {
            clearInterval(beepInterval);
            beepInterval = null;
        }
    }

    // Process video in 5-second intervals with real-time alerts
    ThermalVisionApp.prototype.processVideoInIntervals = async function () {
        console.log('🎬 Starting interval-based video processing...');

        const videoDuration = await this.getVideoDuration(this.selectedFile);
        console.log(`📹 Video duration: ${videoDuration}s`);

        const intervalDuration = 5;
        const totalIntervals = Math.ceil(videoDuration / intervalDuration);

        this.showIntervalProgress(true);

        // Auto-Play: Start video playback
        const videoPlayer = document.getElementById('previewPlayer');
        if (videoPlayer) {
            console.log('▶️ Auto-playing video for real-time monitoring');
            videoPlayer.currentTime = 0;
            videoPlayer.play().catch(e => console.warn('Auto-play failed:', e));
        }

        let allIntervalResults = [];
        let currentInterval = 0;

        // Synchronization variables
        let processingIntervalEnd = 0;
        let isProcessing = false;

        // Handler to pause video if it runs ahead of analysis
        const syncHandler = () => {
            if (isProcessing && videoPlayer && !videoPlayer.paused && videoPlayer.currentTime >= processingIntervalEnd) {
                console.log(`⏸️ Video paused for sync at ${videoPlayer.currentTime.toFixed(1)}s (waiting for analysis)`);
                videoPlayer.pause();
                // Prevent drifting too far past the interval end
                if (videoPlayer.currentTime > processingIntervalEnd + 0.5) {
                    videoPlayer.currentTime = processingIntervalEnd;
                }
            }
        };

        if (videoPlayer) {
            videoPlayer.addEventListener('timeupdate', syncHandler);
        }

        try {
            while (currentInterval < totalIntervals) {
                const startTime = currentInterval * intervalDuration;
                const endTime = Math.min((currentInterval + 1) * intervalDuration, videoDuration);

                // Set sync target for this interval
                processingIntervalEnd = endTime;
                isProcessing = true;

                // Sync: Wait for video to reach the start of this interval
                // This ensures we don't analyze ahead of what the user is seeing
                if (videoPlayer) {
                    // If video was paused by sync handler, resume it now that we are starting this interval
                    if (videoPlayer.paused && videoPlayer.currentTime < videoDuration) {
                        console.log('▶️ Resuming video for next interval');
                        videoPlayer.play().catch(e => console.warn('Resume failed:', e));
                    }

                    while (videoPlayer.currentTime < startTime && !videoPlayer.paused && !videoPlayer.ended) {
                        await new Promise(r => setTimeout(r, 200));
                    }
                }

                console.log(`🔄 Processing interval ${currentInterval + 1}/${totalIntervals}: ${startTime}s - ${endTime}s`);

                this.updateIntervalProgress(currentInterval + 1, totalIntervals, startTime, endTime);

                const intervalResult = await this.processInterval(startTime, endTime);

                // Analysis done for this chunk, allow video to proceed
                isProcessing = false;

                // If video was paused because it hit the limit, resume it immediately
                if (videoPlayer && videoPlayer.paused && videoPlayer.currentTime >= processingIntervalEnd && videoPlayer.currentTime < videoDuration) {
                    console.log('▶️ Analysis done, resuming video');
                    videoPlayer.play().catch(e => console.warn('Resume failed:', e));
                }

                allIntervalResults.push(intervalResult);

                console.log(`✅ Interval ${currentInterval + 1} complete:`, intervalResult);
                console.log(`   Label changed: ${intervalResult.label_changed}`);

                if (!intervalResult.label_changed) {
                    console.warn(`⚠️ No movement detected in interval ${startTime}s-${endTime}s`);

                    // Save alert to history when no movement detected
                    const alertId = this.saveIntervalAlert(startTime, endTime, intervalResult.dominant_position, intervalResult);

                    // Continuous Analysis: Show alert WITHOUT awaiting (non-blocking)
                    this.showIntervalAlert(startTime, endTime, intervalResult.dominant_position, alertId);
                    console.log('✅ Alert triggered, continuing analysis immediately...');
                } else {
                    console.log(`✅ Movement detected, continuing automatically`);
                }

                currentInterval++;
            }

            console.log('🎉 All intervals processed successfully!');
            this.hideIntervalProgress();

            const finalResults = this.compileFinalResults(allIntervalResults);
            this.displayResults(finalResults);

            // Save final analysis to history
            this.saveIntervalAnalysisToHistory(finalResults, allIntervalResults);

            document.getElementById('successMessage').style.display = 'flex';
            this.showNotification('Video analysis completed successfully!', 'success');

        } catch (error) {
            console.error('❌ Interval processing error:', error);
            this.hideIntervalProgress();
            throw error;
        } finally {
            // Cleanup
            if (videoPlayer) {
                videoPlayer.removeEventListener('timeupdate', syncHandler);
                console.log('⏹️ Analysis finished, stopping video');
                videoPlayer.pause();
            }
        }
    };

    // Process a single interval
    ThermalVisionApp.prototype.processInterval = async function (startTime, endTime) {
        const formData = new FormData();
        formData.append('file', this.selectedFile);
        formData.append('start_time', startTime.toString());
        formData.append('end_time', endTime.toString());

        const response = await fetch(`${this.API_BASE}/predict_video_interval`, {
            method: 'POST',
            body: formData
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Interval processing failed: ${response.status} - ${errorText}`);
        }

        const data = await response.json();
        if (data.error) throw new Error(data.error);
        return data;
    };

    // Show alert modal and wait for acknowledgment
    ThermalVisionApp.prototype.showIntervalAlert = async function (startTime, endTime, position, alertId) {
        return new Promise((resolve) => {
            let modal = document.getElementById('intervalAlertModal');
            if (!modal) modal = this.createIntervalAlertModal();

            document.getElementById('alertIntervalTime').textContent = `${startTime}s - ${endTime}s`;
            document.getElementById('alertCurrentPosition').textContent = position;
            document.getElementById('alertIntervalPatient').textContent = this.currentPatient ? this.currentPatient.name : 'Unknown';

            // Store alertId on the modal for acknowledgment
            modal.dataset.currentAlertId = alertId || '';

            modal.style.display = 'block';

            // ENHANCED AUDIO PLAYBACK - LOOPING
            console.warn('🔊 Attempting to play looping alert sound...');
            const alertSound = document.getElementById('alertSound');

            // Start fallback beep loop
            startBeepLoop();

            if (alertSound) {
                alertSound.pause();
                alertSound.currentTime = 0;
                alertSound.volume = 1.0;
                alertSound.loop = true; // Enable looping

                const playPromise = alertSound.play();
                if (playPromise !== undefined) {
                    playPromise
                        .then(() => {
                            console.log('✅ HTML5 Audio playing (looping)');
                            // If HTML5 audio works, stop the fallback beep to avoid double sound
                            stopBeepLoop();
                        })
                        .catch(err => {
                            console.warn('⚠️ HTML5 Audio failed:', err);
                            // Fallback beep loop continues
                        });
                }
            }

            const acknowledgeBtn = document.getElementById('acknowledgeIntervalBtn');
            const newAcknowledgeBtn = acknowledgeBtn.cloneNode(true);
            acknowledgeBtn.parentNode.replaceChild(newAcknowledgeBtn, acknowledgeBtn);

            newAcknowledgeBtn.addEventListener('click', () => {
                console.log('🔘 Acknowledge button clicked');
                modal.style.display = 'none';

                // Record click history
                const currentAlertId = modal.dataset.currentAlertId;
                if (currentAlertId) {
                    this.recordAlertClick(currentAlertId);
                }

                // Stop all sounds
                if (alertSound) {
                    alertSound.pause();
                    alertSound.currentTime = 0;
                    alertSound.loop = false;
                }
                stopBeepLoop();

                resolve();
            });
        });
    };

    // Record alert click history
    ThermalVisionApp.prototype.recordAlertClick = function (alertId) {
        console.log(`📝 Recording alert click for ID: ${alertId}`);

        // Update backend
        if (this.API_BASE) {
            fetch(`${this.API_BASE}/api/alert/acknowledge`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id: alertId,
                    acknowledged_by: this.currentUser ? this.currentUser.username : 'User'
                })
            })
                .then(res => res.json())
                .then(data => console.log('✅ Backend acknowledgment response:', data))
                .catch(err => console.warn('⚠️ Backend acknowledgment failed:', err));
        }

        // Update localStorage
        try {
            const alerts = JSON.parse(localStorage.getItem('intervalAlerts') || '[]');
            const alertIndex = alerts.findIndex(a => a.id === alertId);
            if (alertIndex !== -1) {
                alerts[alertIndex].clickedAt = new Date().toISOString();
                alerts[alertIndex].status = 'clicked';
                localStorage.setItem('intervalAlerts', JSON.stringify(alerts));
                console.log('✅ Alert click recorded in localStorage');
            }
        } catch (e) {
            console.error('Error updating alert click history:', e);
        }
    };

    // Save interval alert to history
    ThermalVisionApp.prototype.saveIntervalAlert = function (startTime, endTime, position, intervalResult) {
        try {
            const alertId = 'alert_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

            // Defensive check for patient
            const patientInfo = this.currentPatient || { name: 'Unknown', id: 'N/A', age: 0, room: 'N/A' };

            // Map predictions to frame_predictions for display compatibility
            let enhancedResult = null;
            if (intervalResult) {
                enhancedResult = {
                    ...intervalResult,
                    frame_predictions: intervalResult.predictions // Map for displayResults
                };
            }

            const alertRecord = {
                id: alertId,
                timestamp: new Date().toISOString(),
                dateTime: new Date().toLocaleString(),
                patientId: patientInfo.id, // Explicit fields for backend validation
                patientName: patientInfo.name,
                position: position,
                duration: (endTime - startTime).toFixed(1),
                analysis_result: enhancedResult ? JSON.stringify(enhancedResult) : null,
                patient: {
                    name: patientInfo.name,
                    id: patientInfo.id,
                    age: patientInfo.age,
                    room: patientInfo.room
                },
                alertType: 'No Movement Detected',
                interval: `${startTime}s - ${endTime}s`,
                intervalStart: startTime,
                intervalEnd: endTime,
                fileName: this.selectedFile ? this.selectedFile.name : 'Unknown',
                fileType: this.selectedFile ? this.selectedFile.type : 'video',
                acknowledged: false, // Initially false
                status: 'pending'
            };

            console.warn('💾 Saving interval alert to history:', alertRecord);

            // Save to backend API
            if (this.API_BASE) {
                fetch(`${this.API_BASE}/api/alert`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(alertRecord)
                })
                    .then(res => res.json())
                    .then(data => console.log('✅ Backend alert response:', data))
                    .catch(err => console.warn('⚠️ Backend save failed:', err));
            }

            // Save to localStorage
            try {
                const alerts = JSON.parse(localStorage.getItem('intervalAlerts') || '[]');
                alerts.push(alertRecord);
                localStorage.setItem('intervalAlerts', JSON.stringify(alerts));
                console.warn('✅ Alert saved to localStorage. Total:', alerts.length);
            } catch (storageErr) {
                console.error('❌ localStorage save failed:', storageErr);
            }

            return alertId; // Return ID for tracking

        } catch (error) {
            console.error('❌ Error saving alert:', error);
            return null;
        }
    };

    // Save final interval analysis to history
    ThermalVisionApp.prototype.saveIntervalAnalysisToHistory = function (finalResults, intervalResults) {
        try {
            const historyId = 'history_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            const patientInfo = this.currentPatient || { name: 'Unknown', id: 'N/A', age: 0, room: 'N/A' };

            const historyRecord = {
                id: historyId,
                timestamp: new Date().toISOString(),
                dateTime: new Date().toLocaleString(),
                patient: {
                    name: patientInfo.name,
                    id: patientInfo.id,
                    age: patientInfo.age,
                    room: patientInfo.room
                },
                fileName: this.selectedFile ? this.selectedFile.name : 'Unknown',
                fileType: 'video',
                prediction: finalResults.prediction,
                confidence: finalResults.confidence,
                totalIntervals: intervalResults.length,
                intervalsWithMovement: intervalResults.filter(i => i.label_changed).length,
                intervalsWithoutMovement: intervalResults.filter(i => !i.label_changed).length,
                movementSummary: finalResults.movement_analysis.summary,
                allIntervals: intervalResults.map(i => ({
                    start: i.interval_start,
                    end: i.interval_end,
                    position: i.dominant_position,
                    changed: i.label_changed
                })),
                // Full analysis result for replay
                analysis_result: JSON.stringify(finalResults)
            };

            console.warn('💾 Saving interval analysis to history:', historyRecord);

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

            try {
                const history = JSON.parse(localStorage.getItem('analysisHistory') || '[]');
                history.push(historyRecord);
                localStorage.setItem('analysisHistory', JSON.stringify(history));
                console.warn('✅ Analysis saved to localStorage. Total:', history.length);
            } catch (storageErr) {
                console.error('❌ localStorage save failed:', storageErr);
            }

        } catch (error) {
            console.error('❌ Error saving analysis:', error);
        }
    };

    // Create alert modal
    ThermalVisionApp.prototype.createIntervalAlertModal = function () {
        const modal = document.createElement('div');
        modal.id = 'intervalAlertModal';
        modal.className = 'modal';
        modal.innerHTML = `
            <div class="modal-content alert-modal">
                <div class="modal-header" style="background: linear-gradient(135deg, #ff6b6b, #ee5a24); color: white;">
                    <h3><i class="fas fa-exclamation-triangle"></i> No Movement Detected</h3>
                </div>
                <div class="modal-body">
                    <div class="alert-interval-info" style="text-align: center; padding: 20px;">
                        <p class="alert-message" style="font-size: 18px; margin-bottom: 20px;">
                            No position change detected in interval <strong id="alertIntervalTime"></strong>
                        </p>
                        <div class="alert-details" style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 20px 0;">
                            <div class="detail-item" style="margin: 10px 0;">
                                <span class="label" style="font-weight: bold;">Current Position:</span>
                                <span class="value" id="alertCurrentPosition" style="color: #1a2a6c; font-size: 20px; font-weight: bold;">-</span>
                            </div>
                            <div class="detail-item" style="margin: 10px 0;">
                                <span class="label" style="font-weight: bold;">Patient:</span>
                                <span class="value" id="alertIntervalPatient">-</span>
                            </div>
                        </div>
                    </div>
                    <div class="form-actions" style="text-align: center;">
                        <button type="button" class="btn btn-primary" id="acknowledgeIntervalBtn" style="padding: 12px 30px; font-size: 16px;">
                            <i class="fas fa-check"></i> Acknowledge & Continue
                        </button>
                    </div>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        return modal;
    };

    // Progress UI functions
    ThermalVisionApp.prototype.showIntervalProgress = function (show) {
        let progressContainer = document.getElementById('videoProgressContainer');
        if (!progressContainer) progressContainer = this.createProgressContainer();
        progressContainer.style.display = show ? 'block' : 'none';
    };

    ThermalVisionApp.prototype.hideIntervalProgress = function () {
        this.showIntervalProgress(false);
    };

    ThermalVisionApp.prototype.createProgressContainer = function () {
        const container = document.createElement('div');
        container.id = 'videoProgressContainer';
        container.innerHTML = `
            <div class="progress-info" style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                <span id="currentInterval" style="font-weight: bold;">Processing 0-5s...</span>
                <span id="progressPercentage" style="color: #1a2a6c; font-weight: bold;">0%</span>
            </div>
            <div class="progress-bar-wrapper" style="background: #e0e0e0; height: 30px; border-radius: 15px; overflow: hidden;">
                <div class="progress-bar-fill" id="videoProgressBar" style="background: linear-gradient(90deg, #1a2a6c, #b21f1f); height: 100%; width: 0%; transition: width 0.3s ease;"></div>
            </div>
        `;

        const loadingIndicator = document.getElementById('loadingIndicator');
        if (loadingIndicator && loadingIndicator.parentNode) {
            loadingIndicator.parentNode.insertBefore(container, loadingIndicator.nextSibling);
        }
        return container;
    };

    ThermalVisionApp.prototype.updateIntervalProgress = function (currentInterval, totalIntervals, startTime, endTime) {
        const percentage = (currentInterval / totalIntervals) * 100;
        document.getElementById('currentInterval').textContent = `Processing ${startTime.toFixed(1)}s - ${endTime.toFixed(1)}s (Interval ${currentInterval}/${totalIntervals})`;
        document.getElementById('progressPercentage').textContent = `${percentage.toFixed(0)}%`;
        document.getElementById('videoProgressBar').style.width = `${percentage}%`;
    };

    // Get video duration
    ThermalVisionApp.prototype.getVideoDuration = async function (file) {
        return new Promise((resolve, reject) => {
            const video = document.createElement('video');
            video.preload = 'metadata';
            video.onloadedmetadata = function () {
                window.URL.revokeObjectURL(video.src);
                resolve(video.duration);
            };
            video.onerror = function () {
                reject(new Error('Failed to load video metadata'));
            };
            video.src = URL.createObjectURL(file);
        });
    };

    // Compile final results
    ThermalVisionApp.prototype.compileFinalResults = function (intervalResults) {
        const allPredictions = [];
        const positionCounts = {};
        let totalConfidence = 0;
        let labelChanges = 0;

        intervalResults.forEach(interval => {
            interval.predictions.forEach(pred => {
                allPredictions.push(pred);
                positionCounts[pred.prediction] = (positionCounts[pred.prediction] || 0) + 1;
                totalConfidence += pred.confidence;
            });
            if (interval.label_changed) labelChanges++;
        });

        const dominantPosition = Object.keys(positionCounts).reduce((a, b) =>
            positionCounts[a] > positionCounts[b] ? a : b
        );

        const avgConfidence = totalConfidence / allPredictions.length;
        const probabilities = {};
        Object.keys(positionCounts).forEach(pos => {
            probabilities[pos] = positionCounts[pos] / allPredictions.length;
        });

        return {
            prediction: dominantPosition,
            confidence: avgConfidence,
            probabilities: probabilities,
            all_classes: Object.keys(positionCounts),
            frame_predictions: allPredictions,
            movement_analysis: {
                movement_detected: labelChanges > 0,
                total_changes: labelChanges,
                summary: labelChanges > 0 ?
                    `Movement detected in ${labelChanges} out of ${intervalResults.length} intervals` :
                    'No movement detected throughout video'
            },
            video_metadata: {
                total_intervals: intervalResults.length,
                interval_duration: 5,
                frames_processed: allPredictions.length
            }
        };
    };

    // Override handlePrediction to use interval processing for videos
    const originalHandlePrediction = ThermalVisionApp.prototype.handlePrediction;
    ThermalVisionApp.prototype.handlePrediction = async function () {
        if (!this.isAuthenticated || !this.currentPatient || !this.selectedFile) {
            if (originalHandlePrediction) return originalHandlePrediction.call(this);
            return;
        }

        const isVideo = this.selectedFile.type.startsWith('video/');

        document.getElementById('resultContainer').style.display = 'none';

        // Hide AI Agent Container
        const agentContainer = document.getElementById('agentContainer');
        if (agentContainer) {
            agentContainer.style.display = 'none';
        }

        document.getElementById('successMessage').style.display = 'none';
        document.getElementById('errorContainer').style.display = 'none';

        try {
            if (isVideo) {
                await this.processVideoInIntervals();
            } else {
                // Use original image processing
                this.showLoading(true);
                const formData = new FormData();
                formData.append('file', this.selectedFile);

                const response = await fetch(`${this.API_BASE}/predict`, {
                    method: 'POST',
                    body: formData
                });

                if (!response.ok) throw new Error(`Server error: ${response.status}`);
                const data = await response.json();
                if (data.error) throw new Error(data.error);

                this.displayResults(data);

                document.getElementById('successMessage').style.display = 'flex';
                this.showNotification('Analysis completed successfully!', 'success');
                this.showLoading(false);
            }
        } catch (error) {
            console.error('❌ Prediction error:', error);
            this.showNotification(`Prediction failed: ${error.message}`, 'error');
            document.getElementById('errorContainer').style.display = 'flex';
            document.getElementById('errorContainer').querySelector('span').textContent = error.message;
            this.showLoading(false);
        }
    };

    console.log('✅ Interval processing module loaded successfully!');
})();