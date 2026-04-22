<?php
session_start();

// Check if user is already logged in
if (isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true) {
    header('Location: dashboard.php');
    exit;
}

$error_message = '';

// Handle login form submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    // Basic validation
    if (empty($username) || empty($password)) {
        $error_message = 'Please fill in all fields.';
    } else {
        // Hardcoded credentials for testing
        $admin_username = 'admin';
        $admin_password = 'admin'; // Updated password for testing
        
        if ($username === $admin_username && $password === $admin_password) {
            // Login successful
            $_SESSION['admin_logged_in'] = true;
            $_SESSION['admin_username'] = $username;
            $_SESSION['login_time'] = time();
            
            header('Location: dashboard.php');
            exit;
        } else {
            $error_message = 'Invalid username or password.';
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UBSAFESTEPS - Admin Login</title>
    <link rel="stylesheet" href="login.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet">
</head>
<body>
    <div class="login-container">
        <div class="login-card">
            <div class="brand-header">
                <div class="brand-title-container">
                    <div class="brand-logo">
                        <img src="logo.png" alt="UBSAFESTEPS Logo">
                    </div>
                    <h1 class="brand-title">UBSAFESTEPS</h1>
                </div>
                <p class="brand-subtitle">Administrator Dashboard Access</p>
            </div>

            <?php if (!empty($error_message)): ?>
                <div class="error-message">
                    <?php echo htmlspecialchars($error_message); ?>
                </div>
            <?php endif; ?>

            <form method="POST" action="" class="login-form">
                <div class="input-group">
                    <input 
                        type="text" 
                        id="username" 
                        name="username" 
                        class="form-input"
                        placeholder="Enter your Username"
                        value="<?php echo htmlspecialchars($_POST['username'] ?? ''); ?>"
                        required
                        autocomplete="username"
                    >
                    <span class="input-icon">👤</span>
                </div>

                <div class="input-group">
                    <input 
                        type="password" 
                        id="password" 
                        name="password" 
                        class="form-input password-field"
                        placeholder="Enter your Password"
                        required
                        autocomplete="current-password"
                    >
                    <span class="input-icon">🔒</span>
                </div>

                <button type="submit" class="signin-btn">
                    Sign In
                </button>
            </form>

            <div class="divider">
                <span>- Admin Access Only -</span>
            </div>

            <div class="footer-actions">
                <button type="button" class="info-btn" onclick="showInfo()">
                     How to Access your Admin Dashboard
                </button>
            </div>
        </div>
    </div>

    <script>
        function showInfo() {
            alert('Admin Dashboard Access Instructions:\n\n1. Enter your assigned administrator username\n2. Enter your secure password\n3. Click "Sign In to Dashboard" to access the system\n\nNote: Only authorized administrators can access this dashboard.\nFor security reasons, your session will expire after inactivity.');
        }

        // Auto-focus on username field
        document.addEventListener('DOMContentLoaded', function() {
            const usernameField = document.getElementById('username');
            if (usernameField) {
                usernameField.focus();
            }
        });

        // Add form validation
        document.querySelector('.login-form').addEventListener('submit', function(e) {
            const username = document.getElementById('username').value.trim();
            const password = document.getElementById('password').value.trim();
            
            if (!username || !password) {
                e.preventDefault();
                alert('Please fill in all fields.');
                return false;
            }

            // Add loading state to button
            const submitBtn = this.querySelector('.signin-btn');
            submitBtn.classList.add('loading');
            submitBtn.textContent = 'Signing In...';
        });

        // Handle form errors by removing loading state
        <?php if (!empty($error_message)): ?>
        document.addEventListener('DOMContentLoaded', function() {
            const submitBtn = document.querySelector('.signin-btn');
            if (submitBtn) {
                submitBtn.classList.remove('loading');
                submitBtn.textContent = 'Sign In to Dashboard';
            }
        });
        <?php endif; ?>
    </script>
</body>
</html>
