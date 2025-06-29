const mongoose = require('mongoose');

const attendanceSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  date: {
    type: Date,
    required: true,
    default: Date.now,
    unique: true, // Ensure only one attendance record per user per day
  },
  checkInTime: {
    type: Date,
    required: true,
  },
  checkOutTime: {
    type: Date,
  },
  breaks: [
    {
      start: { type: Date, required: true },
      end: { type: Date },
      duration: { type: Number, default: 0 }, // Duration in milliseconds
      type: {
        type: String,
        enum: ['lunch', 'coffee', 'personal', 'medical', 'smoke', 'other'],
        default: 'other'
      },
      reason: { type: String, maxlength: 200 }, // Optional reason for the break
      approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, // Admin who approved/started
    },
  ],
  totalBreakDuration: {
    type: Number,
    default: 0, // Total duration in milliseconds
  },
  status: {
    type: String,
    enum: ['present', 'absent', 'leave', 'half-day'],
    default: 'present',
  },
  // Potentially add location data, remarks, etc.
}, { timestamps: true });

const Attendance = mongoose.model('Attendance', attendanceSchema);

module.exports = Attendance;