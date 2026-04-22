<?php
/**
 * API Endpoint: Get PredefinedZones from Firebase
 * Returns JSON data of all predefined zones
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
    $zones = $firebase->getAllPredefinedZones();
    
    // Format zones data
    $formattedZones = [];
    foreach ($zones as $zone) {
        $formattedZones[] = $firebase->formatPredefinedZoneData($zone);
    }
    
    echo json_encode([
        'success' => true,
        'zones' => $formattedZones,
        'count' => count($formattedZones)
    ]);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Failed to fetch predefined zones: ' . $e->getMessage()
    ]);
}


