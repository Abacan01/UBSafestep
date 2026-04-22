<?php
session_start();

// Destroy the session
$_SESSION = array(); // Clear session variables
session_destroy(); // Destroy the session

// Redirect to login page
header('Location: login.php');
exit;
?>
