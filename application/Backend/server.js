const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3001;
const JWT_SECRET = 'your-secret-key-change-in-production';

// Middleware
app.use(cors());
app.use(express.json());

// Initialize SQLite database
const dbPath = path.join(__dirname, 'users.db');
const db = new sqlite3.Database(dbPath);

// Create users table if it doesn't exist
db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    fullName TEXT NOT NULL,
    phone TEXT,
    createdAt DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);
});

// Routes
app.get('/api/health', (req, res) => {
  res.json({ status: 'Server is running!' });
});

// Register
app.post('/api/register', async (req, res) => {
  try {
    const { username, email, password, fullName, phone } = req.body;
    if (!username || !email || !password || !fullName) {
      return res.status(400).json({ success: false, message: 'All required fields must be filled' });
    }

    db.get('SELECT * FROM users WHERE username = ? OR email = ?', [username, email], async (err, row) => {
      if (err) return res.status(500).json({ success: false, message: 'Database error' });
      if (row) return res.status(400).json({ success: false, message: 'Username or email already exists' });

      const hashedPassword = await bcrypt.hash(password, 10);
      db.run(
        'INSERT INTO users (username, email, password, fullName, phone) VALUES (?, ?, ?, ?, ?)',
        [username, email, hashedPassword, fullName, phone || null],
        function (err) {
          if (err) return res.status(500).json({ success: false, message: 'Failed to create user' });
          res.status(201).json({ success: true, message: 'User created successfully', userId: this.lastID });
        }
      );
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Login
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ success: false, message: 'Username and password required' });

  db.get('SELECT * FROM users WHERE username = ? OR email = ?', [username, username], async (err, row) => {
    if (err) return res.status(500).json({ success: false, message: 'Database error' });
    if (!row) return res.status(401).json({ success: false, message: 'Invalid credentials' });

    const isValidPassword = await bcrypt.compare(password, row.password);
    if (!isValidPassword) return res.status(401).json({ success: false, message: 'Invalid credentials' });

    const token = jwt.sign({ userId: row.id, username: row.username, email: row.email }, JWT_SECRET, { expiresIn: '24h' });

    res.json({
      success: true,
      message: 'Login successful',
      token,
      user: { id: row.id, username: row.username, email: row.email, fullName: row.fullName, phone: row.phone }
    });
  });
});

// Profile (protected)
app.get('/api/profile', authenticateToken, (req, res) => {
  db.get(
    'SELECT id, username, email, fullName, phone, createdAt FROM users WHERE id = ?',
    [req.user.userId],
    (err, row) => {
      if (err) return res.status(500).json({ success: false, message: 'Database error' });
      if (!row) return res.status(404).json({ success: false, message: 'User not found' });
      res.json({ success: true, user: row });
    }
  );
});

// JWT Middleware
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ success: false, message: 'Access token required' });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ success: false, message: 'Invalid or expired token' });
    req.user = user;
    next();
  });
}

// Serve frontend files
// app.use(express.static(path.join(__dirname, '../Frontend')));

// Default route to index.html
// app.get('/', (req, res) => {
//   res.sendFile(path.join(__dirname, '../Frontend/index.html'));
// });

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on http://0.0.0.0:${PORT}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down server...');
  db.close((err) => {
    if (err) console.error('Error closing database:', err);
    else console.log('Database connection closed.');
    process.exit(0);
  });
});
