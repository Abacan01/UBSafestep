<?php
/**
 * Firebase Service Class
 * Handles all Firestore database operations
 */

class FirebaseService {
    private $projectId;
    private $apiKey;
    private $firestoreUrl;
    private $studentsCollection;
    private $predefinedZonesCollection;
    
    public function __construct() {
        // Load configuration from firebase_config.php
        $config = require __DIR__ . '/firebase_config.php';
        
        // Set properties from config
        $this->projectId = $config['project_id'] ?? 'ubsafestep-2200983';
        $this->apiKey = $config['api_key'] ?? null;
        $this->firestoreUrl = $config['firestore_url'] ?? "https://firestore.googleapis.com/v1/projects/{$this->projectId}/databases/(default)/documents";
        $this->studentsCollection = $config['students_collection'] ?? 'Students';
        $this->predefinedZonesCollection = $config['predefinedzones_collection'] ?? 'PredefinedZones';
    }
    
    /**
     * Fetch all students from Firestore
     * @return array Array of student data
     */
    public function getAllStudents() {
        try {
            // Firestore REST API endpoint
            $url = $this->firestoreUrl . '/' . $this->studentsCollection;
            
            // Add API key as query parameter
            if ($this->apiKey) {
                $url .= '?key=' . $this->apiKey;
            }
            
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json'
            ]);
            
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($httpCode !== 200) {
                error_log("Firestore API Error: HTTP $httpCode - $response");
                return [];
            }
            
            $data = json_decode($response, true);
            
            if (!isset($data['documents']) || !is_array($data['documents'])) {
                return [];
            }
            
            // Convert Firestore documents to array
            $students = [];
            foreach ($data['documents'] as $document) {
                $student = $this->parseFirestoreDocument($document);
                if ($student) {
                    $students[] = $student;
                }
            }
            
            return $students;
            
        } catch (Exception $e) {
            error_log("Firestore Error: " . $e->getMessage());
            return [];
        }
    }
    
    /**
     * Parse Firestore document structure to array
     */
    private function parseFirestoreDocument($document) {
        if (!isset($document['fields'])) {
            return null;
        }
        
        $student = [];
        
        // Extract document ID (last part of the name path)
        if (isset($document['name'])) {
            $nameParts = explode('/', $document['name']);
            $student['id'] = end($nameParts);
        }
        
        // Parse Firestore field values
        foreach ($document['fields'] as $fieldName => $fieldValue) {
            $student[$fieldName] = $this->extractFirestoreValue($fieldValue);
        }
        
        return $student;
    }
    
    /**
     * Extract value from Firestore field structure
     */
    private function extractFirestoreValue($fieldValue) {
        // Firestore stores values with type information
        if (isset($fieldValue['stringValue'])) {
            return $fieldValue['stringValue'];
        } elseif (isset($fieldValue['integerValue'])) {
            return (int)$fieldValue['integerValue'];
        } elseif (isset($fieldValue['doubleValue'])) {
            return (float)$fieldValue['doubleValue'];
        } elseif (isset($fieldValue['booleanValue'])) {
            return (bool)$fieldValue['booleanValue'];
        } elseif (isset($fieldValue['timestampValue'])) {
            // Convert Firestore timestamp to Unix timestamp
            return strtotime($fieldValue['timestampValue']);
        } elseif (isset($fieldValue['nullValue'])) {
            return null;
        }
        
        return null;
    }
    
    /**
     * Format student data for display
     * Matches your Firestore field names: FirstName, LastName, StudentID, YearLevel, etc.
     */
    public function formatStudentData($student) {
        // Combine FirstName and LastName
        $fullName = trim(($student['FirstName'] ?? '') . ' ' . ($student['LastName'] ?? ''));
        if (empty($fullName)) {
            $fullName = 'Unknown';
        }
        
        // Get StudentID
        $studentId = $student['StudentID'] ?? $student['id'] ?? '';
        
        // Map YearLevel to grade and level
        $yearLevel = $student['YearLevel'] ?? null;
        $level = $this->mapYearLevelToLevel($yearLevel);
        $grade = $this->mapYearLevelToGrade($yearLevel);
        
        // Get attendance status (if available in your data)
        // You may need to add attendance tracking in your Flutter app
        $status = $student['status'] ?? $student['attendanceStatus'] ?? $student['isPresent'] ?? 'absent';
        
        // Get time in/out (if available)
        $timeIn = $student['timeIn'] ?? $student['checkInTime'] ?? $student['timeInTimestamp'] ?? null;
        $timeOut = $student['timeOut'] ?? $student['checkOutTime'] ?? $student['timeOutTimestamp'] ?? null;
        
        // Format time for display
        $timeInFormatted = $this->formatTimeForDisplay($timeIn);
        $timeOutFormatted = $this->formatTimeForDisplay($timeOut);
        
        return [
            'id' => $student['id'] ?? $studentId,
            'name' => $fullName,
            'studentId' => $studentId,
            'level' => $level,
            'grade' => $grade,
            'status' => $status,
            'timeIn' => $timeInFormatted,
            'timeOut' => $timeOutFormatted,
            'duration' => $this->calculateDuration($timeIn, $timeOut),
            // Additional fields from Firestore
            'firstName' => $student['FirstName'] ?? '',
            'lastName' => $student['LastName'] ?? '',
            'email' => $student['UBmail'] ?? '',
            'yearLevel' => $yearLevel,
            'createdAt' => $student['createdAt'] ?? null,
            'updatedAt' => $student['updatedAt'] ?? null,
        ];
    }
    
    /**
     * Map YearLevel to Students Level (Elementary, Junior Highschool, Senior Highschool)
     */
    private function mapYearLevelToLevel($yearLevel) {
        if ($yearLevel === null) {
            return '';
        }
        
        // YearLevel 1-6 = Elementary
        if ($yearLevel >= 1 && $yearLevel <= 6) {
            return 'Elementary';
        }
        // YearLevel 7-10 = Junior Highschool
        elseif ($yearLevel >= 7 && $yearLevel <= 10) {
            return 'Junior Highschool';
        }
        // YearLevel 11-12 = Senior Highschool
        elseif ($yearLevel >= 11 && $yearLevel <= 12) {
            return 'Senior Highschool';
        }
        
        return '';
    }
    
    /**
     * Map YearLevel to Grade Level (Grade 1, Grade 2, etc.)
     */
    private function mapYearLevelToGrade($yearLevel) {
        if ($yearLevel === null) {
            return '';
        }
        
        return 'Grade ' . $yearLevel;
    }
    
    /**
     * Format time value for display
     */
    private function formatTimeForDisplay($time) {
        if (!$time || $time === '--') {
            return '--';
        }
        
        try {
            // If it's a timestamp (numeric or string of numbers)
            if (is_numeric($time) || (is_string($time) && ctype_digit($time))) {
                // Handle both seconds and milliseconds timestamps
                $timestamp = (int)$time;
                if ($timestamp > 1000000000000) {
                    // Milliseconds timestamp, convert to seconds
                    $timestamp = $timestamp / 1000;
                }
                return date('h:i A', $timestamp);
            }
            
            // If it's already a formatted time string, return as is
            if (is_string($time)) {
                return $time;
            }
            
            return '--';
        } catch (Exception $e) {
            return '--';
        }
    }
    
    /**
     * Calculate duration between time in and time out
     */
    private function calculateDuration($timeIn, $timeOut) {
        if (!$timeIn) {
            return '--';
        }
        
        try {
            // Convert timeIn to timestamp
            if (is_numeric($timeIn) || (is_string($timeIn) && ctype_digit($timeIn))) {
                $in = (int)$timeIn;
                // Handle milliseconds timestamp
                if ($in > 1000000000000) {
                    $in = $in / 1000;
                }
            } else {
                $in = strtotime($timeIn);
                if ($in === false) {
                    return '--';
                }
            }
            
            // Convert timeOut to timestamp (or use current time if not set)
            if ($timeOut) {
                if (is_numeric($timeOut) || (is_string($timeOut) && ctype_digit($timeOut))) {
                    $out = (int)$timeOut;
                    // Handle milliseconds timestamp
                    if ($out > 1000000000000) {
                        $out = $out / 1000;
                    }
                } else {
                    $out = strtotime($timeOut);
                    if ($out === false) {
                        $out = time(); // Use current time if parsing fails
                    }
                }
            } else {
                $out = time(); // Use current time if timeOut is not set
            }
            
            $diff = $out - $in;
            
            if ($diff < 0) {
                return '--';
            }
            
            $hours = floor($diff / 3600);
            $minutes = floor(($diff % 3600) / 60);
            
            return $hours . 'h ' . $minutes . 'm';
        } catch (Exception $e) {
            error_log("Duration calculation error: " . $e->getMessage());
            return '--';
        }
    }
    
    /**
     * Fetch all predefined zones from Firestore
     * @return array Array of predefined zone data
     */
    public function getAllPredefinedZones() {
        try {
            // Firestore REST API endpoint
            $url = $this->firestoreUrl . '/' . $this->predefinedZonesCollection;
            
            // Add API key as query parameter
            if ($this->apiKey) {
                $url .= '?key=' . $this->apiKey;
            }
            
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json'
            ]);
            
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($httpCode !== 200) {
                error_log("Firestore API Error: HTTP $httpCode - $response");
                return [];
            }
            
            $data = json_decode($response, true);
            
            if (!isset($data['documents']) || !is_array($data['documents'])) {
                return [];
            }
            
            // Convert Firestore documents to array
            $zones = [];
            foreach ($data['documents'] as $document) {
                $zone = $this->parseFirestoreDocument($document);
                if ($zone) {
                    $zones[] = $zone;
                }
            }
            
            return $zones;
            
        } catch (Exception $e) {
            error_log("Firestore Error: " . $e->getMessage());
            return [];
        }
    }
    
    /**
     * Format predefined zone data for display
     */
    public function formatPredefinedZoneData($zone) {
        // Extract document ID
        $zoneId = $zone['id'] ?? '';
        
        // Get zone fields
        $safezoneId = $zone['SafezoneID'] ?? $zone['safezoneID'] ?? '';
        $radius = $zone['Radius'] ?? $zone['radius'] ?? null;
        $timeIn = $zone['TimeIn'] ?? $zone['timeIn'] ?? null;
        $timeOut = $zone['TimeOut'] ?? $zone['timeOut'] ?? null;
        $duration = $zone['duration'] ?? null;
        
        // Format time for display (if it's already a string like "09:20", keep it)
        $timeInFormatted = $this->formatTimeForDisplay($timeIn);
        $timeOutFormatted = $this->formatTimeForDisplay($timeOut);
        
        // If duration is not provided, calculate it from TimeIn and TimeOut
        if (!$duration && $timeIn && $timeOut) {
            $duration = $this->calculateDuration($timeIn, $timeOut);
        } elseif ($duration && is_string($duration)) {
            // Keep duration as is if it's already formatted (e.g., "1h 0m")
            $duration = $duration;
        } elseif (!$duration) {
            $duration = '--';
        }
        
        return [
            'id' => $zoneId,
            'safezoneId' => $safezoneId,
            'radius' => $radius,
            'timeIn' => $timeInFormatted,
            'timeOut' => $timeOutFormatted,
            'duration' => $duration,
            // Additional fields
            'rawTimeIn' => $timeIn,
            'rawTimeOut' => $timeOut,
        ];
    }
}
