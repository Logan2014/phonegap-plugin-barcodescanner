﻿cordova.define("phonegap-plugin-barcodescanner.BarcodeScannerProxy", function(require, exports, module) {
/*
 * Copyright (c) Microsoft Open Technologies, Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
 */

var urlutil = require('cordova/urlutil');

var CAMERA_STREAM_STATE_CHECK_RETRY_TIMEOUT = 200; // milliseconds
var OPERATION_IS_IN_PROGRESS = -2147024567;
var INITIAL_FOCUS_DELAY = 200; // milliseconds
var CHECK_PLAYING_TIMEOUT = 100; // milliseconds

/**
 * List of supported barcode formats from ZXing library. Used to return format
 *   name instead of number code as per plugin spec.
 *
 * @enum {String}
 */
var BARCODE_FORMAT = {
    1: 'AZTEC',
    2: 'CODABAR',
    4: 'CODE_39',
    8: 'CODE_93',
    16: 'CODE_128',
    32: 'DATA_MATRIX',
    64: 'EAN_8',
    128: 'EAN_13',
    256: 'ITF',
    512: 'MAXICODE',
    1024: 'PDF_417',
    2048: 'QR_CODE',
    4096: 'RSS_14',
    8192: 'RSS_EXPANDED',
    16384: 'UPC_A',
    32768: 'UPC_E',
    61918: 'All_1D',
    65536: 'UPC_EAN_EXTENSION',
    131072: 'MSI',
    262144: 'PLESSEY'
};

var zXingBarcodeFormat = {
    'AZTEC': ZXing.BarcodeFormat.aztec,
    'CODABAR': ZXing.BarcodeFormat.codabar,
    'CODE_39': ZXing.BarcodeFormat.code_39,
    'CODE_93': ZXing.BarcodeFormat.code_93,
    'CODE_128': ZXing.BarcodeFormat.code_128,
    'DATA_MATRIX': ZXing.BarcodeFormat.data_MATRIX,
    'EAN_8': ZXing.BarcodeFormat.ean_8,
    'EAN_13': ZXing.BarcodeFormat.ean_13,
    'ITF': ZXing.BarcodeFormat.itf,
    'MAXICODE': ZXing.BarcodeFormat.maxicode,
    'PDF_417': ZXing.BarcodeFormat.pdf_417,
    'QR_CODE': ZXing.BarcodeFormat.qr_CODE,
    'RSS_14': ZXing.BarcodeFormat.rss_14,
    'RSS_EXPANDED': ZXing.BarcodeFormat.rss_EXPANDED,
    'UPC_A': ZXing.BarcodeFormat.upc_A,
    'UPC_E': ZXing.BarcodeFormat.upc_E,
    'All_1D': ZXing.BarcodeFormat.all_1D,
    'UPC_EAN_EXTENSION': ZXing.BarcodeFormat.upc_EAN_EXTENSION,
    'MSI': ZXing.BarcodeFormat.msi,
    'PLESSEY': ZXing.BarcodeFormat.plessey
};

/**
 * Detects the first appropriate camera located at the back panel of device. If
 *   there is no back cameras, returns the first available.
 *
 * @returns {Promise<String>} Camera id
 */
function findCamera() {
    var Devices = Windows.Devices.Enumeration;

    // Enumerate cameras and add them to the list
    return Devices.DeviceInformation.findAllAsync(Devices.DeviceClass.videoCapture)
    .then(function (cameras) {

        if (!cameras || cameras.length === 0) {
            throw new Error("No cameras found");
        }

        var backCameras = cameras.filter(function (camera) {
            return camera.enclosureLocation && camera.enclosureLocation.panel === Devices.Panel.back;
        });

        // If there is back cameras, return the id of the first,
        // otherwise take the first available device's id
        return (backCameras[0] || cameras[0]).id;
    });
}

/**
 * @param {Windows.Graphics.Display.DisplayOrientations} displayOrientation
 * @return {Number}
 */
function videoPreviewRotationLookup(displayOrientation, isMirrored) {
    var degreesToRotate;

    switch (displayOrientation) {
        case Windows.Graphics.Display.DisplayOrientations.landscape:
            degreesToRotate = 0;
            break;
        case Windows.Graphics.Display.DisplayOrientations.portrait:
            if (isMirrored) {
                degreesToRotate = 270;
            } else {
                degreesToRotate = 90;
            }
            break;
        case Windows.Graphics.Display.DisplayOrientations.landscapeFlipped:
            degreesToRotate = 180;
            break;
        case Windows.Graphics.Display.DisplayOrientations.portraitFlipped:
            if (isMirrored) {
                degreesToRotate = 90;
            } else {
                degreesToRotate = 270;
            }
            break;
        default:
            degreesToRotate = 0;
            break;
    }

    return degreesToRotate;
}

/**
 * The pure JS implementation of barcode reader from WinRTBarcodeReader.winmd.
 *   Works only on Windows 10 devices and more efficient than original one.
 *
 * @class {BarcodeReader}
 */
function BarcodeReader (formats) {
    this._promise = null;
    this._cancelled = false;
    this._manualInput = null;
    this._formats = formats || [];
}

/**
 * Returns an instance of Barcode reader, depending on capabilities of Media
 *   Capture API
 *
 * @static
 * @constructs {BarcodeReader}
 *
 * @param   {MediaCapture}   mediaCaptureInstance  Instance of
 *   Windows.Media.Capture.MediaCapture class
 *
 * @return  {BarcodeReader}  BarcodeReader instance that could be used for
 *   scanning
 */
BarcodeReader.get = function (mediaCaptureInstance, formats) {
    if (mediaCaptureInstance.getPreviewFrameAsync && ZXing.BarcodeReader) {
        return new BarcodeReader(formats);
    }

    // If there is no corresponding API (Win8/8.1/Phone8.1) use old approach with WinMD library
    return new WinRTBarcodeReader.Reader();
};

/**
 * Initializes instance of reader.
 *
 * @param   {MediaCapture}  capture  Instance of
 *   Windows.Media.Capture.MediaCapture class, used for acquiring images/ video
 *   stream for barcode scanner.
 * @param   {Number}  width    Video/image frame width
 * @param   {Number}  height   Video/image frame height
 */
BarcodeReader.prototype.init = function (capture, width, height) {
    this._capture = capture;
    this._width = width;
    this._height = height;
    this._zxingReader = new ZXing.BarcodeReader();
    this._zxingReader.autoRotate = false;
    this._zxingReader.tryInverted = false;
    this._zxingReader.options.possibleFormats = this._formats.map(function (format) {
        return zXingBarcodeFormat[format];
    });
};

/**
 * Starts barcode search routines asyncronously.
 *
 * @return  {Promise<ScanResult>}  barcode scan result or null if search
 *   cancelled.
 */
BarcodeReader.prototype.readCode = function () {

    /**
     * Grabs a frame from preview stream uning Win10-only API and tries to
     *   get a barcode using zxing reader provided. If there is no barcode
     *   found, returns null.
     */
    function scanBarcodeAsync(mediaCapture, zxingReader, frameWidth, frameHeight) {
        // Shortcuts for namespaces
        var Imaging = Windows.Graphics.Imaging;
        var Streams = Windows.Storage.Streams;

        var frame = new Windows.Media.VideoFrame(Imaging.BitmapPixelFormat.gray8, frameWidth, frameHeight);
        return mediaCapture.getPreviewFrameAsync(frame)
            .then(WinJS.Utilities.Scheduler.schedulePromiseIdle)
            .then(function (capturedFrame) {
                // Copy captured frame to buffer for further deserialization
                var bitmap = capturedFrame.softwareBitmap;
                var rawBuffer = new Streams.Buffer(bitmap.pixelWidth * bitmap.pixelHeight);
                capturedFrame.softwareBitmap.copyToBuffer(rawBuffer);
                capturedFrame.close();

                // Get raw pixel data from buffer
                var data = new Uint8Array(rawBuffer.length);
                var dataReader = Streams.DataReader.fromBuffer(rawBuffer);
                dataReader.readBytes(data);
                dataReader.close();
                var result = zxingReader.decode(data, frameWidth, frameHeight, ZXing.BitmapFormat.gray8);
                return result;
            });
    }

    var self = this;
    return scanBarcodeAsync(this._capture, this._zxingReader, this._width, this._height)
    .then(function (result) {
        if (self._manualInput) {
            return {
                text: self._manualInput
            };
        }

        if (self._cancelled) {
            return null;
        }

        return result || (self._promise = self.readCode());
    });
};

/**
 * Stops barcode search
 */
BarcodeReader.prototype.stop = function (manualInput) {
    this._cancelled = true;
    this._manualInput = manualInput;
};

function degreesToRotation(degrees) {
    switch (degrees) {
        // portrait
        case 90:
            return Windows.Media.Capture.VideoRotation.clockwise90Degrees;
        // landscape
        case 0:
            return Windows.Media.Capture.VideoRotation.none;
        // portrait-flipped
        case 270:
            return Windows.Media.Capture.VideoRotation.clockwise270Degrees;
        // landscape-flipped
        case 180:
            return Windows.Media.Capture.VideoRotation.clockwise180Degrees;
        default:
            // Falling back to portrait default
            return Windows.Media.Capture.VideoRotation.clockwise90Degrees;
    }
}

module.exports = {

    /**
     * Scans image via device camera and retieves barcode from it.
     * @param  {function} success Success callback
     * @param  {function} fail    Error callback
     * @param  {array} args       Arguments array
     */
    scan: function (success, fail, args) {
        var capturePreview,
            capturePreviewAlignmentMark,
            captureCancelButton,
            navigationButtonsDiv,
            previewMirroring,
            capture,
            reader;

        function updatePreviewForRotation(evt) {
            if (!capture) {
                return;
            }

            var displayInformation = (evt && evt.target) || Windows.Graphics.Display.DisplayInformation.getForCurrentView();
            var currentOrientation = displayInformation.currentOrientation;

            previewMirroring = capture.getPreviewMirroring();

            // Lookup up the rotation degrees.
            var rotDegree = videoPreviewRotationLookup(currentOrientation, previewMirroring);

            capture.setPreviewRotation(degreesToRotation(rotDegree));
            return WinJS.Promise.as();
        }

        /**
         * Creates a preview frame and necessary objects
         */
        function createPreview() {

            // Create fullscreen preview
            var capturePreviewFrameStyle = document.createElement('link');
            capturePreviewFrameStyle.rel = "stylesheet";
            capturePreviewFrameStyle.type = "text/css";
            capturePreviewFrameStyle.href = urlutil.makeAbsolute("/www/css/plugin-barcodeScanner.css");

            document.head.appendChild(capturePreviewFrameStyle);

            capturePreviewFrame = document.createElement('div');
            capturePreviewFrame.className = "barcode-scanner-wrap";

            capturePreviewAlignmentMark = document.createElement('div');
            capturePreviewAlignmentMark.className = "barcode-scanner-mark";

            navigationButtonsDiv = document.createElement("div");
            navigationButtonsDiv.className = "barcode-scanner-app-bar";

            var hint = document.createElement("div");
            hint.innerText = "Якщо штрих-код не розпізнається, то введіть номер вручну:";
            hint.className = "hint";
            navigationButtonsDiv.appendChild(hint);

            var inputPanel = document.createElement("div");
            inputPanel.className = "code-input-panel";

            var input = document.createElement("input");
            input.placeholder = "наприклад 001020300";
            input.addEventListener('input', updateUI);
            inputPanel.appendChild(input);

            capturePreview = document.createElement("video");
            capturePreview.className = "barcode-scanner-preview";
            capturePreview.addEventListener('click', function () {
                focus();
                input.blur();
            });

            var action = document.createElement("button");
            action.innerText = "Відправити";
            action.addEventListener('click', function () {
                reader && reader.stop(input.value);
            });
            inputPanel.appendChild(action);

            navigationButtonsDiv.appendChild(inputPanel);

            BarcodeReader.scanCancelled = false;
            document.addEventListener('backbutton', cancelPreview, false);

            [capturePreview, capturePreviewAlignmentMark, navigationButtonsDiv].forEach(function (element) {
                capturePreviewFrame.appendChild(element);
            });

            updateUI();

            function updateUI() {
                action.disabled = !input.value;
            }
        }

        function focus(controller) {

            var result = WinJS.Promise.wrap();

            if (!capturePreview || capturePreview.paused) {
                // If the preview is not yet playing, there is no sense in running focus
                return result;
            }

            if (!controller) {
                try {
                    controller = capture && capture.videoDeviceController;
                } catch (err) {
                    console.log('Failed to access focus control for current camera: ' + err);
                    return result;
                }
            }

            if (!controller.focusControl || !controller.focusControl.supported) {
                console.log('Focus control for current camera is not supported');
                return result;
            }

            // Multiple calls to focusAsync leads to internal focusing hang on some Windows Phone 8.1 devices
            if (controller.focusControl.focusState === Windows.Media.Devices.MediaCaptureFocusState.searching) {
                return result;
            }

            // The delay prevents focus hang on slow devices
            return WinJS.Promise.timeout(INITIAL_FOCUS_DELAY)
            .then(function () {
                try {
                    return controller.focusControl.focusAsync();
                } catch (e) {
                    // This happens on mutliple taps
                    if (e.number !== OPERATION_IS_IN_PROGRESS) {
                        console.error('focusAsync failed: ' + e);
                        return WinJS.Promise.wrapError(e);
                    }
                    return result;
                }
            });
        }

        function setupFocus(focusControl) {

            function supportsFocusMode(mode) {
                return focusControl.supportedFocusModes.indexOf(mode).returnValue;
            }

            if (!focusControl || !focusControl.supported || !focusControl.configure) {
                return WinJS.Promise.wrap();
            }

            var FocusMode = Windows.Media.Devices.FocusMode;
            var focusConfig = new Windows.Media.Devices.FocusSettings();
            focusConfig.autoFocusRange = Windows.Media.Devices.AutoFocusRange.normal;

            // Determine a focus position if the focus search fails:
            focusConfig.disableDriverFallback = false;

            if (supportsFocusMode(FocusMode.continuous)) {
                console.log("Device supports continuous focus mode");
                focusConfig.mode = FocusMode.continuous;
            } else if (supportsFocusMode(FocusMode.auto)) {
                console.log("Device doesn\'t support continuous focus mode, switching to autofocus mode");
                focusConfig.mode = FocusMode.auto;
            }

            focusControl.configure(focusConfig);

            // Continuous focus should start only after preview has started. See 'Remarks' at 
            // https://msdn.microsoft.com/en-us/library/windows/apps/windows.media.devices.focuscontrol.configure.aspx
            function waitForIsPlaying() {
                var isPlaying = !capturePreview.paused && !capturePreview.ended && capturePreview.readyState > 2;

                if (!isPlaying) {
                    return WinJS.Promise.timeout(CHECK_PLAYING_TIMEOUT)
                    .then(function () {
                        return waitForIsPlaying();
                    });
                }

                return focus();
            }

            return waitForIsPlaying();
        }

        function disableZoomAndScroll() {
            document.body.classList.add('no-zoom');
            document.body.classList.add('no-scroll');
        }

        function enableZoomAndScroll() {
            document.body.classList.remove('no-zoom');
            document.body.classList.remove('no-scroll');
        }

        /**
         * Starts stream transmission to preview frame and then run barcode search
         */
        function startPreview() {
            return findCamera()
            .then(function (id) {
                var captureSettings = new Windows.Media.Capture.MediaCaptureInitializationSettings();
                captureSettings.streamingCaptureMode = Windows.Media.Capture.StreamingCaptureMode.video;
                captureSettings.photoCaptureSource = Windows.Media.Capture.PhotoCaptureSource.videoPreview;
                captureSettings.videoDeviceId = id;

                capture = new Windows.Media.Capture.MediaCapture();
                return capture.initializeAsync(captureSettings);
            })
            .then(function () {

                var controller = capture.videoDeviceController;
                var deviceProps = controller.getAvailableMediaStreamProperties(Windows.Media.Capture.MediaStreamType.videoRecord);

                deviceProps = Array.prototype.slice.call(deviceProps);
                deviceProps = deviceProps.filter(function (prop) {
                    // filter out streams with "unknown" subtype - causes errors on some devices
                    return prop.subtype !== "Unknown";
                }).sort(function (propA, propB) {
                    // sort properties by resolution
                    return propB.width - propA.width;
                });

                var maxResProps = deviceProps[0];
                return controller.setMediaStreamPropertiesAsync(Windows.Media.Capture.MediaStreamType.videoRecord, maxResProps)
                .then(function () {
                    return {
                        capture: capture,
                        width: maxResProps.width,
                        height: maxResProps.height
                    };
                });
            })
            .then(function (captureSettings) {

                capturePreview.msZoom = true;
                capturePreview.src = URL.createObjectURL(capture);
                capturePreview.play();

                // Insert preview frame and controls into page
                document.body.appendChild(capturePreviewFrame);

                disableZoomAndScroll();

                return setupFocus(captureSettings.capture.videoDeviceController.focusControl)
                .then(function () {
                    Windows.Graphics.Display.DisplayInformation.getForCurrentView().addEventListener("orientationchanged", updatePreviewForRotation, false);
                    return updatePreviewForRotation();
                })
                .then(function () {

                    if (!Windows.Media.Devices.CameraStreamState) {
                        // CameraStreamState is available starting with Windows 10 so skip this check for 8.1
                        // https://msdn.microsoft.com/en-us/library/windows/apps/windows.media.devices.camerastreamstate
                        return WinJS.Promise.as();
                    }

                    function checkCameraStreamState() {
                        if (capture.cameraStreamState !== Windows.Media.Devices.CameraStreamState.streaming) {

                            // Using loop as MediaCapture.CameraStreamStateChanged does not fire with CameraStreamState.streaming state.
                            return WinJS.Promise.timeout(CAMERA_STREAM_STATE_CHECK_RETRY_TIMEOUT)
                            .then(function () {
                                return checkCameraStreamState();
                            });
                        }

                        return WinJS.Promise.as();
                    }

                    // Ensure CameraStreamState is Streaming
                    return checkCameraStreamState();
                })
                .then(function () {
                    return captureSettings;
                });
            });
        }

        /**
         * Removes preview frame and corresponding objects from window
         */
        function destroyPreview() {

            Windows.Graphics.Display.DisplayInformation.getForCurrentView().removeEventListener("orientationchanged", updatePreviewForRotation, false);
            document.removeEventListener('backbutton', cancelPreview);

            capturePreview.pause();
            capturePreview.src = null;

            if (capturePreviewFrame) {
                document.body.removeChild(capturePreviewFrame);
            }

            reader && reader.stop();
            reader = null;

            capture && capture.stopRecordAsync();
            capture = null;

            enableZoomAndScroll();
        }

        /**
         * Stops preview and then call success callback with cancelled=true
         * See https://github.com/phonegap-build/BarcodeScanner#using-the-plugin
         */
        function cancelPreview(backbuttonEvent) {
            BarcodeReader.scanCancelled = true;
            reader && reader.stop();
        }

        function checkCancelled() {
            if (BarcodeReader.scanCancelled) {
                throw new Error('Canceled');
            }
        }

        WinJS.Promise.wrap(createPreview())
        .then(function () {
            checkCancelled();
            return startPreview();
        })
        .then(function (captureSettings) {
            checkCancelled();
            var formats = [];
            if (args.length) {
                formats = args[0].formats;
                formats = formats && formats.split(',');
            }

            reader = BarcodeReader.get(captureSettings.capture, formats);
            reader.init(captureSettings.capture, captureSettings.width, captureSettings.height);

            // Add a small timeout before capturing first frame otherwise
            // we would get an 'Invalid state' error from 'getPreviewFrameAsync'
            return WinJS.Promise.timeout(200)
            .then(function () {
                checkCancelled();
                return reader.readCode();
            });
        })
        .done(function (result) {
            destroyPreview();
            success({
                text: result && result.text,
                format: result && BARCODE_FORMAT[result.barcodeFormat],
                cancelled: !result
            });
        }, function (error) {
            destroyPreview();

            if (error.message == 'Canceled') {
                success({
                    cancelled: true
                });
            } else {
                fail(error);
            }
        });
    },

    /**
     * Encodes specified data into barcode
     * @param  {function} success Success callback
     * @param  {function} fail    Error callback
     * @param  {array} args       Arguments array
     */
    encode: function (success, fail, args) {
        fail("Not implemented yet");
    }
};

require("cordova/exec/proxy").add("BarcodeScanner", module.exports);

});
