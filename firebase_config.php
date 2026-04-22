<?php
/**
 * Firebase Configuration
 * 
 * Replace these values with your Firebase project credentials
 * You can find these in your Firebase Console:
 * Project Settings > General > Your apps > Web app config
 */

return [
    // Firebase Project ID
    'project_id' => 'ubsafestep-2200983',
    
    // Firebase Web API Key
    'api_key' => 'AIzaSyC_m7_6F7O3ias5HUWRZMg2ZmCGW3divUI',
    
    // Firestore Database URL (REST API)
    'firestore_url' => 'https://firestore.googleapis.com/v1/projects/ubsafestep-2200983/databases/(default)/documents',
    
    // Collection name where students are stored
    'students_collection' => 'Students',
    
    // Collection name where predefined zones are stored
    'predefinedzones_collection' => 'PredefinedZones',
    
    // Service Account (if using Admin SDK)
    'service_account_path' => __DIR__ . '/serviceAccountKey.json',
];

