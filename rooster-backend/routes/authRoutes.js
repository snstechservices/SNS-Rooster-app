const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const User = require('../models/User');
const auth = require('../middleware/auth');
const upload = require('../middleware/upload');
const path = require('path');
const fs = require('fs');
const router = express.Router();

// Login route
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    // Find user by email
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    // Check if user is active
    if (!user.isActive) {
      return res.status(401).json({ message: 'Account is deactivated' });
    }

    // Verify password
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    // Update last login
    user.lastLogin = new Date();
    await user.save();

    // Generate JWT token
    console.log('DEBUG: Starting token generation');
    console.log('DEBUG: User data for token:', {
      userId: user._id,
      email: user.email,
      role: user.role,
      isProfileComplete: user.isProfileComplete
    });
    console.log('DEBUG: JWT_SECRET during token generation:', process.env.JWT_SECRET);
    console.log('DEBUG: User data passed to jwt.sign:', {
      userId: user._id,
      email: user.email,
      role: user.role,
      isProfileComplete: user.isProfileComplete
    });

    if (!process.env.JWT_SECRET) {
      console.error('ERROR: JWT_SECRET is not defined in environment variables');
      return res.status(500).json({ message: 'Server configuration error: Missing JWT_SECRET' });
    }

    try {
      const token = jwt.sign(
        {
          userId: user._id,
          email: user.email,
          role: user.role,
          isProfileComplete: user.isProfileComplete
        },
        process.env.JWT_SECRET,
        { expiresIn: '24h' }
      );
      console.log('DEBUG: Token generated successfully:', token);
      res.json({
        token,
        user: user.getPublicProfile()
      });
    } catch (error) {
      console.error('DEBUG: Error during token generation:', error);
      res.status(500).json({ message: 'Server error during token generation' });
    }
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Register route (admin only)
router.post('/register', auth, async (req, res) => {
  try {
    // Check if requester is admin
    if (req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Only admins can register new users' });
    }

    const { email, password, firstName, lastName, role, department, position } = req.body; // Changed name to firstName, lastName

    // Check if user already exists
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(400).json({ message: 'Email already registered' });
    }

    // Create new user
    const user = new User({
      email,
      password,
      firstName, // Added firstName
      lastName, // Added lastName
      role: role || 'employee',
      department,
      position,
      isProfileComplete: false
    });

    await user.save();

    res.status(201).json({
      message: 'User registered successfully',
      user: user.getPublicProfile()
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Request password reset
router.post('/reset-password', async (req, res) => {
  try {
    const { email } = req.body;
    const user = await User.findOne({ email });

    if (!user) {
      // Don't reveal if email exists or not
      return res.json({ message: 'If your email is registered, you will receive password reset instructions' });
    }

    // Generate reset token
    const resetToken = crypto.randomBytes(32).toString('hex');
    user.resetPasswordToken = resetToken;
    user.resetPasswordExpires = Date.now() + 3600000; // 1 hour
    await user.save();

    // TODO: Send email with reset token
    // For now, just return the token (in production, send via email)
    res.json({ 
      message: 'Password reset instructions sent to your email',
      // Remove this in production
      resetToken: process.env.NODE_ENV === 'development' ? resetToken : undefined
    });
  } catch (error) {
    console.error('Password reset request error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Reset password with token
router.post('/reset-password/:token', async (req, res) => {
  try {
    const { token } = req.params;
    const { password } = req.body;

    const user = await User.findOne({
      resetPasswordToken: token,
      resetPasswordExpires: { $gt: Date.now() }
    });

    if (!user) {
      return res.status(400).json({ message: 'Invalid or expired reset token' });
    }

    // Update password and clear reset token
    user.password = password;
    user.resetPasswordToken = undefined;
    user.resetPasswordExpires = undefined;
    await user.save();

    res.json({ message: 'Password has been reset successfully' });
  } catch (error) {
    console.error('Password reset error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Get current user profile
router.get('/me', auth, async (req, res) => {
  try {
    const user = await User.findById(req.user.userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    res.json({ user: user.getPublicProfile() });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Update current user profile
router.patch('/me', auth, async (req, res) => {
  try {
    console.log('PATCH /me request body:', req.body);
    console.log('Authenticated user:', req.user);

    const user = await User.findById(req.user.userId);
    if (!user) {
      console.log('User not found');
      return res.status(404).json({ message: 'User not found' });
    }

    const updates = req.body;
    const allowedUpdates = ['name', 'firstName', 'lastName', 'email', 'phone', 'address', 'emergencyContact', 'emergencyPhone'];
    const isValidOperation = Object.keys(updates).every((update) => allowedUpdates.includes(update));

    if (!isValidOperation) {
      console.log('Invalid updates:', updates);
      return res.status(400).json({ message: 'Invalid updates' });
    }

    // Prevent duplicate email errors
    if (updates.email && updates.email !== user.email) {
      const emailExists = await User.findOne({ email: updates.email });
      if (emailExists) {
        console.log('Duplicate email detected:', updates.email);
        return res.status(400).json({ message: 'Email already exists' });
      }
    }

    // Handle name field for backward compatibility
    if (updates.name && !updates.firstName && !updates.lastName) {
      const nameParts = updates.name.trim().split(' ');
      updates.firstName = nameParts[0] || '';
      updates.lastName = nameParts.slice(1).join(' ') || '';
      delete updates.name;
    }

    Object.keys(updates).forEach((update) => {
      user[update] = updates[update];
    });

    user.recalculateProfileComplete();
    await user.save();
    console.log('Updated user profile:', user);
    res.json({ profile: user.getPublicProfile() });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Get all users (admin/manager only, with optional role filter)
router.get('/users', auth, async (req, res) => {
  try {
    // Check if requester is admin or manager
    if (req.user.role !== 'admin' && req.user.role !== 'manager') {
      return res.status(403).json({ message: 'Only admins and managers can view users' });
    }

    const { role } = req.query;
    let query = {};
    if (role) {
      query.role = role;
    }

    const users = await User.find(query).select('-password'); // Exclude password field
    res.json({ users: users.map(user => user.getPublicProfile()) });
  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Update user (admin or self-update)
router.patch('/users/:id', auth, async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    // Check if requester is admin or the user themselves
    if (req.user.role !== 'admin' && req.user.userId !== id) {
      return res.status(403).json({ message: 'Unauthorized to update this user' });
    }

    // Prevent password update via this route (use reset-password route instead)
    if (updates.password) {
      return res.status(400).json({ message: 'Password cannot be updated via this route. Use /reset-password instead.' });
    }

    // Find user and update
    const user = await User.findById(id);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Apply updates
    Object.keys(updates).forEach(update => {
      user[update] = updates[update];
    });
    user.recalculateProfileComplete();
    await user.save();

    res.json({
      message: 'User updated successfully',
      user: user.getPublicProfile()
    });
  } catch (error) {
    console.error('User update error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Delete user (admin only)
router.delete('/users/:id', auth, async (req, res) => {
  try {
    // Check if requester is admin
    if (req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Only admins can delete users' });
    }

    const { id } = req.params;
    const user = await User.findByIdAndDelete(id);

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('User deletion error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Upload profile picture
router.post('/users/profile/picture', auth, upload.single('profilePicture'), async (req, res) => {
  console.log('=== PROFILE PICTURE UPLOAD START ===');
  console.log('Request received for profile picture upload');
  console.log('User ID:', req.user?.userId);
  console.log('File received:', req.file ? 'YES' : 'NO');
  
  if (req.file) {
    console.log('File details:', {
      filename: req.file.filename,
      originalname: req.file.originalname,
      mimetype: req.file.mimetype,
      size: req.file.size,
      path: req.file.path,
      destination: req.file.destination
    });
  }
  
  try {
    if (!req.file) {
      console.log('ERROR: No file uploaded');
      return res.status(400).json({ message: 'No file uploaded' });
    }

    const user = await User.findById(req.user.userId);
    if (!user) {
      console.log('ERROR: User not found');
      return res.status(404).json({ message: 'User not found' });
    }

    console.log('User found:', user.email);
    console.log('Current avatar:', user.avatar);

    // Store old avatar info before updating
    const oldAvatarPath = user.avatar ? path.join(__dirname, '../uploads/avatars', path.basename(user.avatar)) : null;
    
    // Update user with new avatar path first
    const avatarUrl = `/uploads/avatars/${req.file.filename}`;
    console.log('New avatar URL:', avatarUrl);
    console.log('File saved to:', req.file.path);
    
    user.avatar = avatarUrl;
    await user.save();
    console.log('User avatar updated in database');

    // Delete old avatar file if it exists (after successful database update)
    if (oldAvatarPath) {
      console.log('Checking old avatar path:', oldAvatarPath);
      if (fs.existsSync(oldAvatarPath)) {
        console.log('Deleting old avatar file');
        fs.unlinkSync(oldAvatarPath);
      } else {
        console.log('Old avatar file does not exist');
      }
    }

    console.log('=== PROFILE PICTURE UPLOAD SUCCESS ===');
    res.json({
      message: 'Profile picture updated successfully',
      profile: user.getPublicProfile()
    });
  } catch (error) {
    console.error('=== PROFILE PICTURE UPLOAD ERROR ===');
    console.error('Profile picture upload error:', error);
    
    // Clean up uploaded file if there was an error
    if (req.file && fs.existsSync(req.file.path)) {
      console.log('Cleaning up uploaded file due to error');
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ message: 'Server error during file upload' });
  }
});

// Upload document (admin and owner only)
router.post('/upload-document', auth, upload.single('file'), async (req, res) => {
  try {
    const { documentType } = req.body;
    const userId = req.user.userId;

    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    if (req.user.role !== 'admin' && req.user.userId !== userId) {
      return res.status(403).json({ message: 'Unauthorized to upload document' });
    }

    const filePath = `/uploads/documents/${req.file.filename}`;
    user.documents = user.documents || [];
    user.documents.push({ type: documentType, path: filePath });
    await user.save();

    res.status(200).json({
      message: 'Document uploaded successfully',
      documentInfo: {
        fileName: req.file.originalname,
        filePath,
      },
    });
  } catch (error) {
    console.error('Document upload error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Debugging route to create a new user (for testing purposes)
router.post('/debug-create-user', async (req, res) => {
  try {
    const { email, password, firstName, lastName, role, department, position } = req.body;

    // Check if user already exists
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(400).json({ message: 'Email already registered' });
    }

    // Validate firstName and lastName
    if (!firstName || !lastName) {
      return res.status(400).json({ message: 'First name and last name are required' });
    }

    // Create new user
    const user = new User({
      email,
      password,
      firstName,
      lastName,
      role: role || 'employee',
      department,
      position,
      isActive: true,
      isProfileComplete: false,
    });

    await user.save();

    res.status(201).json({
      message: 'User created successfully',
      user: user.getPublicProfile(),
    });
  } catch (error) {
    console.error('Debug create user error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;