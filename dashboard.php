<?php
session_start();

// Check if user is logged in
if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    header('Location: login.php');
    exit;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UBSAFESTEPS - Admin Dashboard</title>
    <link rel="stylesheet" href="dashboard.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
</head>
<body>
    <!-- Sidebar -->
    <aside class="sidebar">
        <div class="sidebar-header">
            <div class="logo">
                <div class="logo-icon">
                    <img src="logo.png" alt="UBSAFESTEPS Logo">
                </div>
                <span class="logo-text">UBSAFESTEPS</span>
            </div>
        </div>
        <nav class="sidebar-nav">
            <ul>
                <li class="nav-item active">
                    <a href="#" class="nav-link">
                        <span class="nav-icon">📊</span>
                        Dashboard
                    </a>
                </li>
                <li class="nav-item">
                    <a href="#" class="nav-link" onclick="logout()">
                        <span class="nav-icon">🚪</span>
                        Logout
                    </a>
                </li>
            </ul>
        </nav>
    </aside>

    <!-- Main Content -->
    <div class="main-wrapper">
        <!-- Top Header -->
        <header class="top-header">
            <div class="header-content">
                <h1 class="page-title">Dashboard</h1>
                <div class="header-actions">
                    <div class="admin-info">
                        <span class="admin-name">Administrator</span>
                        <div class="admin-avatar">A</div>
                    </div>
                </div>
            </div>
        </header>

        <!-- Main Content Area -->
        <main class="content-area">
            <!-- Student Tracking Section -->
            <div class="section-card">
                <div class="section-header">
                    <h2>Student Tracking</h2>
                    <div class="last-updated">
                        Last updated: <span id="lastUpdated">2025-08-17 14:30:25</span>
                    </div>
                </div>

                <!-- Controls -->
                <div class="controls-section">
                    <div class="search-group">
                        <input type="text" id="searchInput" placeholder="Search by student name or ID..." class="search-input">
                    </div>
                    <div class="filters-group">
                        <select id="levelFilter" class="filter-select">
                            <option value="">All Levels</option>
                            <option value="Elementary">Elementary</option>
                            <option value="Junior Highschool">Junior Highschool</option>
                            <option value="Senior Highschool">Senior Highschool</option>
                        </select>
                        <select id="gradeFilter" class="filter-select">
                            <option value="">All Grades</option>
                        </select>
                        <select id="statusFilter" class="filter-select">
                            <option value="">All Status</option>
                            <option value="present">Present</option>
                            <option value="absent">Absent</option>
                        </select>
                        <button class="refresh-btn" onclick="refreshData()">Refresh</button>
                    </div>
                </div>

                <!-- Data Table -->
                <div class="table-container">
                    <table class="data-table" id="studentsTable">
                        <thead>
                            <tr>
                                <th>Student Name</th>
                                <th>Students Level</th>
                                <th>Grade Level</th>
                                <th>Status</th>
                                <th>Time In</th>
                                <th>Time Out</th>
                                <th>Duration</th>
                            </tr>
                        </thead>
                        <tbody id="studentsTableBody">
                        </tbody>
                    </table>
                </div>

                <!-- Table Footer -->
                <div class="table-footer">
                    <div class="entries-info">
                        Showing <span id="entriesStart">0</span> to <span id="entriesEnd">0</span> of <span id="entriesTotal">0</span> entries
                    </div>
                    <div class="pagination">
                        <button class="page-btn" onclick="previousPage()">Previous</button>
                        <button class="page-btn active">1</button>
                        <button class="page-btn">2</button>
                        <button class="page-btn">3</button>
                        <button class="page-btn" onclick="nextPage()">Next</button>
                    </div>
                </div>
            </div>
        </main>
    </div>

    <script>
        let allStudents = [];
        let filteredStudents = [];
        let currentPage = 1;
        const itemsPerPage = 10;
        
        // Load students on page load
        document.addEventListener('DOMContentLoaded', function() {
            loadStudents();
            // Auto refresh every 30 seconds
            setInterval(refreshData, 30000);
        });
        
        // Load students from Firebase
        async function loadStudents() {
            try {
                const response = await fetch('api/get_students.php');
                const data = await response.json();
                
                if (data.success && data.students) {
                    allStudents = data.students;
                    filteredStudents = data.students;
                    currentPage = 1; // Reset to first page when data loads
                    renderStudents();
                    updateEntriesInfo();
                    updatePagination();
                } else {
                    console.error('Error loading students:', data.error);
                    document.getElementById('studentsTableBody').innerHTML = 
                        '<tr><td colspan="7" style="text-align: center; padding: 20px;">No students found or error loading data.</td></tr>';
                }
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('studentsTableBody').innerHTML = 
                    '<tr><td colspan="7" style="text-align: center; padding: 20px;">Error connecting to Firebase. Please check your configuration.</td></tr>';
            }
        }
        
        // Render students in the table
        function renderStudents() {
            const tbody = document.getElementById('studentsTableBody');
            const startIndex = (currentPage - 1) * itemsPerPage;
            const endIndex = startIndex + itemsPerPage;
            const studentsToShow = filteredStudents.slice(startIndex, endIndex);
            
            if (studentsToShow.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 20px;">No students found.</td></tr>';
                return;
            }
            
            tbody.innerHTML = studentsToShow.map(student => {
                const statusClass = student.status === 'present' ? 'present' : 'absent';
                const statusText = student.status === 'present' ? 'Present' : 'Absent';
                
                return `
                    <tr class="table-row ${statusClass}">
                        <td class="name-cell">
                            <div class="student-name">${escapeHtml(student.name)}</div>
                            <div class="student-id">${escapeHtml(student.studentId)}</div>
                        </td>
                        <td>${escapeHtml(student.level || '--')}</td>
                        <td>${escapeHtml(student.grade || '--')}</td>
                        <td><span class="status-badge ${statusClass}">${statusText}</span></td>
                        <td>${formatTime(student.timeIn)}</td>
                        <td>${formatTime(student.timeOut)}</td>
                        <td>${escapeHtml(student.duration || '--')}</td>
                    </tr>
                `;
            }).join('');
        }
        
        // Format time for display
        function formatTime(time) {
            if (!time || time === '--') return '--';
            
            // If it's a timestamp, convert it
            if (typeof time === 'number' || /^\d+$/.test(time)) {
                const date = new Date(parseInt(time) * 1000);
                return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
            }
            
            // If it's already a string, return as is
            return time;
        }
        
        // Escape HTML to prevent XSS
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Update entries info
        function updateEntriesInfo() {
            const total = filteredStudents.length;
            const start = total === 0 ? 0 : (currentPage - 1) * itemsPerPage + 1;
            const end = Math.min(currentPage * itemsPerPage, total);
            
            document.getElementById('entriesStart').textContent = start;
            document.getElementById('entriesEnd').textContent = end;
            document.getElementById('entriesTotal').textContent = total;
        }
        
        function refreshData() {
            document.getElementById('lastUpdated').textContent = new Date().toLocaleString();
            loadStudents();
        }
        
        function logout() {
            if (confirm('Are you sure you want to logout?')) {
                window.location.href = 'logout.php'; // Redirect to logout.php
            }
        }
        
        function previousPage() {
            if (currentPage > 1) {
                currentPage--;
                renderStudents();
                updateEntriesInfo();
                updatePagination();
            }
        }
        
        function nextPage() {
            const totalPages = Math.ceil(filteredStudents.length / itemsPerPage);
            if (currentPage < totalPages) {
                currentPage++;
                renderStudents();
                updateEntriesInfo();
                updatePagination();
            }
        }
        
        function updatePagination() {
            const totalPages = Math.ceil(filteredStudents.length / itemsPerPage);
            const pagination = document.querySelector('.pagination');
            
            if (!pagination) return;
            
            // Clear existing page number buttons (keep Previous and Next)
            const existingButtons = pagination.querySelectorAll('.page-btn:not([onclick*="previousPage"]):not([onclick*="nextPage"])');
            existingButtons.forEach(btn => btn.remove());
            
            // Find Previous and Next buttons
            const prevBtn = pagination.querySelector('[onclick*="previousPage"]');
            const nextBtn = pagination.querySelector('[onclick*="nextPage"]');
            
            // Disable/enable Previous button
            if (prevBtn) {
                prevBtn.disabled = currentPage === 1;
                prevBtn.style.opacity = currentPage === 1 ? '0.5' : '1';
                prevBtn.style.cursor = currentPage === 1 ? 'not-allowed' : 'pointer';
            }
            
            // Disable/enable Next button
            if (nextBtn) {
                nextBtn.disabled = currentPage === totalPages || totalPages === 0;
                nextBtn.style.opacity = (currentPage === totalPages || totalPages === 0) ? '0.5' : '1';
                nextBtn.style.cursor = (currentPage === totalPages || totalPages === 0) ? 'not-allowed' : 'pointer';
            }
            
            // Generate page number buttons
            if (totalPages > 0) {
                // Show max 5 page numbers at a time
                let startPage = Math.max(1, currentPage - 2);
                let endPage = Math.min(totalPages, startPage + 4);
                
                // Adjust start if we're near the end
                if (endPage - startPage < 4) {
                    startPage = Math.max(1, endPage - 4);
                }
                
                // Insert page number buttons before Next button
                for (let i = startPage; i <= endPage; i++) {
                    const pageBtn = document.createElement('button');
                    pageBtn.className = 'page-btn';
                    pageBtn.textContent = i;
                    if (i === currentPage) {
                        pageBtn.classList.add('active');
                    }
                    pageBtn.onclick = () => goToPage(i);
                    
                    if (nextBtn) {
                        nextBtn.parentNode.insertBefore(pageBtn, nextBtn);
                    } else {
                        pagination.appendChild(pageBtn);
                    }
                }
            }
        }
        
        function goToPage(page) {
            const totalPages = Math.ceil(filteredStudents.length / itemsPerPage);
            if (page >= 1 && page <= totalPages) {
                currentPage = page;
                renderStudents();
                updateEntriesInfo();
                updatePagination();
            }
        }
        
        // Search functionality - now searches all students, not just visible ones
        document.getElementById('searchInput').addEventListener('input', function() {
            applySearchAndFilters();
        });
        
        function applySearchAndFilters() {
            const searchTerm = document.getElementById('searchInput').value.toLowerCase().trim();
            const levelFilter = document.getElementById('levelFilter').value;
            const gradeFilter = document.getElementById('gradeFilter').value;
            const statusFilter = document.getElementById('statusFilter').value;
            
            // Filter the allStudents array based on search and filters
            filteredStudents = allStudents.filter(student => {
                let show = true;
                
                // Apply search filter
                if (searchTerm) {
                    const name = (student.name || '').toLowerCase();
                    const studentId = (student.studentId || '').toLowerCase();
                    if (!name.includes(searchTerm) && !studentId.includes(searchTerm)) {
                        show = false;
                    }
                }
                
                // Apply level filter
                if (show && levelFilter && student.level !== levelFilter) {
                    show = false;
                }
                
                // Apply grade filter
                if (show && gradeFilter && student.grade !== gradeFilter) {
                    show = false;
                }
                
                // Apply status filter
                if (show && statusFilter && student.status !== statusFilter) {
                    show = false;
                }
                
                return show;
            });
            
            // Reset to page 1 when filters/search change
            currentPage = 1;
            renderStudents();
            updateEntriesInfo();
            updatePagination();
        }
        
        // Grade filter options based on level
        const gradeOptions = {
            'Elementary': ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'],
            'Junior Highschool': ['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10'],
            'Senior Highschool': ['Grade 11', 'Grade 12']
        };
        
        // Update grade filter when level filter changes
        document.getElementById('levelFilter').addEventListener('change', function() {
            const level = this.value;
            const gradeFilter = document.getElementById('gradeFilter');
            
            // Clear existing options except "All Grades"
            gradeFilter.innerHTML = '<option value="">All Grades</option>';
            
            // Add grade options based on selected level
            if (level && gradeOptions[level]) {
                gradeOptions[level].forEach(grade => {
                    const option = document.createElement('option');
                    option.value = grade;
                    option.textContent = grade;
                    gradeFilter.appendChild(option);
                });
            }
            
            applyFilters();
        });
        
        // Filter functionality
        document.querySelectorAll('.filter-select').forEach(select => {
            select.addEventListener('change', applyFilters);
        });
        
        function applyFilters() {
            applySearchAndFilters();
        }
        
    </script>
</body>
</html>
