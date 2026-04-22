<?php
/**
 * Debug endpoint to see PredefinedZones structure
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

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
    
    // Get raw zones data
    $zones = $firebase->getAllPredefinedZones();
    
    // Get students
    $students = $firebase->getAllStudents();
    
    $result = [
        'zones_count' => count($zones),
        'students_count' => count($students),
        'zones' => [],
        'students_emails' => [],
        'matching_analysis' => []
    ];
    
    // Show all zones with extracted identifiers
    foreach ($zones as $zone) {
        $zoneInfo = [
            'document_id' => $zone['id'] ?? 'N/A',
            'all_fields' => $zone,
        ];
        
        // Extract student ID from document ID
        $extractedStudentId = null;
        if (isset($zone['id']) && preg_match('/^(\d+)/', $zone['id'], $matches)) {
            $extractedStudentId = $matches[1];
        }
        
        $zoneInfo['extracted_student_id_from_doc_id'] = $extractedStudentId;
        $zoneInfo['has_email_field'] = !empty($zone['UBmail'] ?? $zone['email'] ?? $zone['Email'] ?? null);
        $zoneInfo['has_studentid_field'] = !empty($zone['StudentID'] ?? $zone['studentID'] ?? null);
        
        $result['zones'][] = $zoneInfo;
    }
    
    // Show all students with their IDs
    foreach ($students as $student) {
        $formatted = $firebase->formatStudentData($student);
        $studentInfo = [
            'name' => $formatted['name'],
            'studentId_formatted' => $formatted['studentId'],
            'studentId_raw' => $student['StudentID'] ?? $student['studentID'] ?? 'N/A',
            'email' => $formatted['email'],
            'raw_email' => $student['UBmail'] ?? $student['email'] ?? 'N/A',
        ];
        
        // Check if this student would match any zone
        $studentId = strtolower(trim($formatted['studentId'] ?? $student['StudentID'] ?? ''));
        $numericStudentId = preg_replace('/[^0-9]/', '', $studentId);
        
        $studentInfo['studentId_normalized'] = $studentId;
        $studentInfo['studentId_numeric'] = $numericStudentId;
        
        // Find matching zones
        $matchingZones = [];
        foreach ($zones as $zone) {
            $zoneId = $zone['id'] ?? '';
            if (preg_match('/^(\d+)/', $zoneId, $matches)) {
                $zoneStudentId = $matches[1];
                if ($zoneStudentId === $numericStudentId || $zoneStudentId === $studentId) {
                    $matchingZones[] = [
                        'document_id' => $zoneId,
                        'timeIn' => $zone['TimeIn'] ?? $zone['timeIn'] ?? 'N/A',
                        'timeOut' => $zone['TimeOut'] ?? $zone['timeOut'] ?? 'N/A',
                        'duration' => $zone['duration'] ?? 'N/A',
                    ];
                }
            }
        }
        $studentInfo['matching_zones'] = $matchingZones;
        
        $result['students_emails'][] = $studentInfo;
    }
    
    echo json_encode($result, JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ]);
}

