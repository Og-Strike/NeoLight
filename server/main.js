const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(() => console.log('Connected to MongoDB'))
.catch(err => console.error('MongoDB connection error:', err));

// Define schema
const neolightSchema = new mongoose.Schema({
  name: String,
  currentMode: String,
  appControlDuration: Number,
  baseBrightness: Number,
  motionBrightness: Number,
  led1Working: Boolean,
  led2Working: Boolean,
  led3Working: Boolean,
  currentPower: Number,
  totalEnergy: Number,
  time: String,
  weather: String,
  sunrise: String,
  sunset: String,
  date: String
}, { collection: 'data' }); // Explicitly use your 'data' collection

const Neolight = mongoose.model('Neolight', neolightSchema);

// API Endpoints
app.get('/api/neolight/:id', async (req, res) => {
  try {
    const device = await Neolight.findOne({ name: req.params.id });
    if (!device) {
      return res.status(404).json({ message: 'Device not found' });
    }
    res.json(device);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.put('/api/neolight/:id', async (req, res) => {
  try {
    const updatedDevice = await Neolight.findOneAndUpdate(
      { name: req.params.id },
      req.body,
      { 
        new: true,
        upsert: true // Create if doesn't exist
      }
    );
    res.json(updatedDevice);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => {
  const address = server.address();
  let fullUrl;
  
  // Handle different environments
  if (typeof address === 'string') {
    fullUrl = address;
  } else {
    const host = process.env.HOST || 'localhost';
    const protocol = process.env.NODE_ENV === 'production' ? 'https' : 'http';
    const port = address.port;
    
    fullUrl = `${protocol}://${host}:${port}`;
    
    // Special handling for localhost with IPv6
    if (host === 'localhost' && address.family === 'IPv6') {
      fullUrl = `${protocol}://[::1]:${port}`;
    }
  }
  
  console.log(`Server running at:`);
  console.log(`- Local: http://localhost:${PORT}`);
});