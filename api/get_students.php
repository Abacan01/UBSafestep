<?php
/**
 * API Endpoint: Get Students from Firebase
 * Returns JSON data of all students
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');

session_start();

// Check if user is logged in
if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized']);
    exit;
}

require_once __DIR__ . '/../firebase_service.php';

try {
    $firebase = new FirebaseService();
    $students = $firebase->getAllStudents();
    
    // Fetch PredefinedZones to match with students by email
    $zones = $firebase->getAllPredefinedZones();
    
    // Debug: Log zones structure (remove in production)
    error_log("PredefinedZones count: " . count($zones));
    if (!empty($zones)) {
        error_log("Sample zone structure: " . json_encode($zones[0]));
    }
    
    // Create maps for different matching strategies
    $zonesByEmail = [];
    $zonesByStudentId = [];
    $zonesByDocumentId = [];
    
    foreach ($zones as $zone) {
        $formattedZone = $firebase->formatPredefinedZoneData($zone);
        
        // Try to find email in zone - check ALL possible field names
        $email = null;
        $studentId = null;
        
        // Check all possible email field variations
        $emailFields = ['UBmail', 'email', 'Email', 'studentEmail', 'UBEmail', 'UB_mail', 'student_email', 'EmailAddress', 'emailAddress'];
        foreach ($emailFields as $field) {
            if (isset($zone[$field]) && !empty($zone[$field])) {
                $email = $zone[$field];
                break;
            }
        }
        
        // Check for StudentID field
        $studentIdFields = ['StudentID', 'studentID', 'studentId', 'student_id', 'Student_ID'];
        foreach ($studentIdFields as $field) {
            if (isset($zone[$field]) && !empty($zone[$field])) {
                $studentId = $zone[$field];
                break;
            }
        }
        
        // Extract student ID from document ID if it starts with a number (e.g., "2200983_UB_ELEMENTARY_DEPT_2026-01-14")
        if (!$studentId && isset($zone['id'])) {
            $zoneId = $zone['id'];
            // Check if document ID starts with numbers (student ID pattern)
            if (preg_match('/^(\d+)/', $zoneId, $matches)) {
                $studentId = $matches[1];
                error_log("Extracted StudentID from document ID: $studentId from $zoneId");
            }
        }
        
        // If no email field found, check if document ID IS the email or contains email
        if (!$email && isset($zone['id'])) {
            $zoneId = $zone['id'];
            // Check if document ID is an email (contains @)
            if (strpos($zoneId, '@') !== false) {
                // Extract email from document ID or use whole ID if it's an email
                if (filter_var($zoneId, FILTER_VALIDATE_EMAIL)) {
                    $email = $zoneId;
                } else {
                    // Try to extract email pattern from ID
                    preg_match('/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/', $zoneId, $matches);
                    if (!empty($matches)) {
                        $email = $matches[0];
                    }
                }
            }
        }
        
        // Map by email
        if ($email) {
            $emailKey = strtolower(trim($email));
            $zonesByEmail[$emailKey] = $formattedZone;
            error_log("Mapped zone for email: $emailKey");
        }
        
        // Map by StudentID (from field or extracted from document ID)
        if ($studentId) {
            $studentIdKey = strtolower(trim($studentId));
            $zonesByStudentId[$studentIdKey] = $formattedZone;
            error_log("Mapped zone for StudentID: $studentIdKey (document ID: " . ($zone['id'] ?? 'N/A') . ")");
        }
        
        // Also map by document ID (in case document ID is the identifier)
        if (isset($zone['id'])) {
            $zonesByDocumentId[$zone['id']] = $formattedZone;
        }
    }
    
    error_log("Total zones mapped by email: " . count($zonesByEmail));
    error_log("Total zones mapped by StudentID: " . count($zonesByStudentId));
    
    // Format students data and merge with PredefinedZones data
    $formattedStudents = [];
    foreach ($students as $student) {
        $formattedStudent = $firebase->formatStudentData($student);
        
        // Get student email - check both formatted and raw data
        $studentEmail = strtolower(trim($formattedStudent['email'] ?? ''));
        
        // Also check raw student data for email
        if (empty($studentEmail)) {
            $studentEmail = strtolower(trim($student['UBmail'] ?? $student['email'] ?? $student['Email'] ?? ''));
        }
        
        // Get student ID - try multiple sources and normalize
        $studentId = $formattedStudent['studentId'] ?? $student['StudentID'] ?? $student['studentID'] ?? '';
        $studentId = strtolower(trim($studentId));
        
        // Also try to get numeric student ID (remove any prefixes like "STU")
        $numericStudentId = preg_replace('/[^0-9]/', '', $studentId);
        if (empty($numericStudentId)) {
            $numericStudentId = $studentId; // Use original if no numbers found
        }
        
        $matchedZone = null;
        $matchMethod = '';
        
        // Try matching by StudentID first (most likely match based on document ID pattern)
        if ($studentId && isset($zonesByStudentId[$studentId])) {
            $matchedZone = $zonesByStudentId[$studentId];
            $matchMethod = 'studentId';
            error_log("MATCH FOUND by STUDENTID (exact) for student: " . $formattedStudent['name'] . " (ID: $studentId)");
        }
        // Try matching by numeric StudentID (in case of format differences)
        elseif ($numericStudentId && $numericStudentId !== $studentId && isset($zonesByStudentId[$numericStudentId])) {
            $matchedZone = $zonesByStudentId[$numericStudentId];
            $matchMethod = 'studentId_numeric';
            error_log("MATCH FOUND by STUDENTID (numeric) for student: " . $formattedStudent['name'] . " (ID: $numericStudentId)");
        }
        // Try matching by email if StudentID didn't match
        elseif ($studentEmail && isset($zonesByEmail[$studentEmail])) {
            $matchedZone = $zonesByEmail[$studentEmail];
            $matchMethod = 'email';
            error_log("MATCH FOUND by EMAIL for student: " . $formattedStudent['name'] . " ($studentEmail)");
        }
        
        // Apply matched zone data
        if ($matchedZone) {
            error_log("Applying zone data - TimeIn: " . ($matchedZone['timeIn'] ?? 'N/A') . ", TimeOut: " . ($matchedZone['timeOut'] ?? 'N/A') . ", Duration: " . ($matchedZone['duration'] ?? 'N/A'));
            
            // Override TimeIn, TimeOut, Duration from PredefinedZones
            $formattedStudent['timeIn'] = $matchedZone['timeIn'] ?? $formattedStudent['timeIn'];
            $formattedStudent['timeOut'] = $matchedZone['timeOut'] ?? $formattedStudent['timeOut'];
            $formattedStudent['duration'] = $matchedZone['duration'] ?? $formattedStudent['duration'];
        } else {
            error_log("NO MATCH for student: " . $formattedStudent['name'] . " (Email: $studentEmail, StudentID: $studentId)");
        }
        
        $formattedStudents[] = $formattedStudent;
    }
    
    echo json_encode([
        'success' => true,
        'students' => $formattedStudents,
        'count' => count($formattedStudents),
        'debug' => [
            'zones_count' => count($zones),
            'zones_mapped' => count($zonesByEmail),
            'sample_zone_keys' => array_slice(array_keys($zonesByEmail), 0, 3)
        ]
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Failed to fetch students: ' . $e->getMessage()
    ]);
}

