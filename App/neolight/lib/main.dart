import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db, DbCollection, where, modify;
import 'dart:async';
import 'package:flutter/animation.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) {
    runApp(NeolightApp());
  });
}

class NeolightApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neolight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: ControlPanel(),
    );
  }
}

class ControlPanel extends StatefulWidget {
  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Db _db;
  late DbCollection _collection;
  bool _isConnected = false;
  bool _isLoading = false;
  String _errorMessage = '';

  // System state
  String currentMode = "manual";
  int appControlDuration = 30;
  int baseBrightness = 30;
  int motionBrightness = 150;

  // LED status
  List<bool> ledWorking = [true, true, true];
  double currentPower = 0.0;
  double totalEnergy = 0.0;

  Timer? _updateTimer;
  late AnimationController _animationController;
  late AnimationController _bgFlowController;
  late Animation<double> _bgFlowAnimation;
  late AnimationController _gradientController;
  late AnimationController _gradientController1;
  late Animation<Color?> _gradientColor1;
  late Animation<Color?> _gradientColor2;
  late Animation<Color?> _gradientColor3;
  late Animation<Color?> _gradientColor4;
  late AnimationController _ledBgController;
  late Animation<Color?> _ledBgAnimation;
  late AnimationController _energyController;
  late Animation<double> _energyScaleAnimation;
  late Animation<Color?> _energyColorAnimation;

  @override
  void initState() {
    super.initState();
    _initMongoDB();
    WidgetsBinding.instance.addObserver(this);

    // Initialize all animation controllers
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    );

    _bgFlowController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 15),
    );

    _gradientController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 20),
    );
    _gradientController1 = AnimationController(
      vsync: this,
      duration: Duration(seconds: 20),
    );

    _ledBgController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    );

    _energyController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );


    _bgFlowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bgFlowController,
        curve: Curves.linear,
      ),
    );

    _gradientColor1 = ColorTween(
      begin: Colors.indigo[800]!.withOpacity(1),
      end: Colors.indigo[600]!.withOpacity(1),
    ).animate(_gradientController);

    _gradientColor2 = ColorTween(
      begin: Colors.purple[600]!.withOpacity(1),
      end: Colors.purple[400]!.withOpacity(1),
    ).animate(_gradientController);

    _gradientColor4 = ColorTween(
      begin: Colors.indigo[800]!.withOpacity(0.8),
      end: Colors.indigo[600]!.withOpacity(0.8),
    ).animate(_gradientController1);

    _gradientColor3 = ColorTween(
      begin: Colors.purple[600]!.withOpacity(0.8),
      end: Colors.purple[400]!.withOpacity(0.8),
    ).animate(_gradientController1);

    _ledBgAnimation = ColorTween(
      begin: Color.fromARGB(255, 255, 255, 255).withOpacity(0.1),
      end: Color.fromARGB(255, 255, 196, 0).withOpacity(0.5),
    ).animate(_ledBgController);

    _energyScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.01), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.01, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _energyController,
      curve: Curves.easeInOut,
    ));

    _energyColorAnimation = ColorTween(
      begin: Colors.deepOrange[700],
      end: Colors.deepOrange[400],
    ).animate(CurvedAnimation(
      parent: _energyController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    _animationController.repeat(reverse: true);
    _bgFlowController.repeat();
    _gradientController.repeat(reverse: true);
    _gradientController1.repeat(reverse: true);
    _ledBgController.repeat(reverse: true);
    _energyController.repeat(reverse: true);

  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _animationController.dispose();
    _bgFlowController.dispose();
    _gradientController.dispose();
    _gradientController1.dispose();
    _ledBgController.dispose();
    _energyController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _db.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadFromMongoDB();
    }
  }

  Future<void> _initMongoDB() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _db = Db("your_mongodb_connection_string");
      await _db.open();

      if (_db.isConnected) {
        _collection = _db.collection('data');
        setState(() {
          _isConnected = true;
        });
        await _loadFromMongoDB();
        _updateTimer = Timer.periodic(
            Duration(seconds: 600), (timer) => _loadFromMongoDB());
      } else {
        throw Exception('Failed to connect to MongoDB');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'MongoDB connection error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFromMongoDB() async {
    if (!_isConnected) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var data = await _collection.findOne(where.eq('name', 'neo'));

      if (data != null) {
        setState(() {
          currentMode = data['currentMode'] ?? "manual";
          appControlDuration = data['appControlDuration'] ?? 30;
          baseBrightness = data['baseBrightness'] ?? 30;
          motionBrightness = data['motionBrightness'] ?? 150;
          ledWorking = [
            data['led1Working'] ?? true,
            data['led2Working'] ?? true,
            data['led3Working'] ?? true,
          ];
          currentPower = data['currentPower']?.toDouble() ?? 0.0;
          totalEnergy = data['totalEnergy']?.toDouble() ?? 0.0;
        });
      } else {
        await _updateMongoDB();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Load error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateMongoDB() async {
    if (!_isConnected) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _collection.update(
        where.eq('name', 'neo'),
        modify
            .set('currentMode', currentMode)
            .set('appControlDuration', appControlDuration)
            .set('baseBrightness', baseBrightness)
            .set('motionBrightness', motionBrightness)
            .set('led1Working', ledWorking[0])
            .set('led2Working', ledWorking[1])
            .set('led3Working', ledWorking[2]),
        upsert: true,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Update error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildModeSelector() {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, child) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [_gradientColor1.value!, _gradientColor2.value!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 3,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings, color: Colors.white.withOpacity(0.8)),
                  SizedBox(width: 10),
                  Text(
                    'Operation Mode',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      'Manual',
                      currentMode == "manual",
                      Icons.touch_app,
                      () {
                        setState(() {
                          currentMode = "manual";
                        });
                        _updateMongoDB();
                      },
                    ),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: _buildModeButton(
                      'App',
                      currentMode == "app",
                      Icons.phone_android,
                      () {
                        setState(() {
                          currentMode = "app";
                        });
                        _updateMongoDB();
                      },
                    ),
                  ),
                ],
              ),
              if (currentMode == "app") ...[
                SizedBox(height: 20),
                Text(
                  'Control Duration: $appControlDuration min',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withOpacity(0.3),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withOpacity(0.2),
                    valueIndicatorColor: Colors.indigo[800],
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 24),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: appControlDuration.toDouble(),
                    min: 1,
                    max: 120,
                    divisions: 119,
                    label: '$appControlDuration',
                    onChanged: (value) {
                      setState(() {
                        appControlDuration = value.toInt();
                      });
                      _updateMongoDB();
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeButton(
      String text, bool isSelected, IconData icon, VoidCallback onPressed) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 15, horizontal: 5),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 28),
                SizedBox(height: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLedStatus(int index) {
    return AnimatedBuilder(
      animation: _ledBgController,
      builder: (context, child) {
        return Container(
          margin: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: ledWorking[index] ? _ledBgAnimation.value : Colors.grey[200],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 1,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: currentMode == "app"
                  ? () {
                      setState(() {
                        ledWorking[index] = !ledWorking[index];
                      });
                      _updateMongoDB();
                    }
                  : null,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ledWorking[index]
                            ? Colors.amber.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.lightbulb_outline,
                        color: ledWorking[index] ? Colors.amber : Colors.grey,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LED ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: ledWorking[index]
                                  ? Colors.blue[900]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            ledWorking[index]
                                ? 'Status: ON - Glowing'
                                : 'Status: OFF - Not working',
                            style: TextStyle(
                              color: ledWorking[index]
                                  ? Colors.blue[800]
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (currentMode == "app")
                      _isLoading
                          ? Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.blue),
                                ),
                              ),
                            )
                          : Transform.scale(
                              scale: 1.2,
                              child: Switch(
                                value: ledWorking[index],
                                onChanged: (value) {
                                  setState(() {
                                    ledWorking[index] = value;
                                  });
                                  _updateMongoDB();
                                },
                                activeColor: Colors.blue,
                                activeTrackColor: Colors.blue[200],
                              ),
                            ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrightnessControl() {
    return currentMode == "app"
        ? AnimatedContainer(
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.teal[700]!, Colors.teal[500]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: EdgeInsets.all(20),
            margin: EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Brightness Control',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                _buildBrightnessSlider(
                  title: 'Base Brightness',
                  value: baseBrightness,
                  min: 0,
                  max: 100,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white.withOpacity(0.3),
                  onChanged: (value) {
                    setState(() {
                      baseBrightness = value.toInt();
                    });
                    _updateMongoDB();
                  },
                ),
                SizedBox(height: 20),
                _buildBrightnessSlider(
                  title: 'Motion Brightness',
                  value: motionBrightness,
                  min: 0,
                  max: 100,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white.withOpacity(0.3),
                  onChanged: (value) {
                    setState(() {
                      motionBrightness = value.toInt();
                    });
                    _updateMongoDB();
                  },
                ),
              ],
            ),
          )
        : SizedBox.shrink();
  }

  Widget _buildBrightnessSlider({
    required String title,
    required int value,
    required int min,
    required int max,
    required Color activeColor,
    required Color inactiveColor,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: $value',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: activeColor,
            inactiveTrackColor: inactiveColor,
            thumbColor: Colors.white,
            overlayColor: Colors.white.withAlpha(0x29),
            valueIndicatorColor: Colors.teal[800],
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 24),
            trackHeight: 6,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildEnergyMonitor() {
    return AnimatedBuilder(
      animation: _energyController,
      builder: (context, child) {
        return Transform.scale(
          scale: _energyScaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  _energyColorAnimation.value!,
                  _energyColorAnimation.value!.withOpacity(0.8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepOrange.withOpacity(0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Energy Monitoring',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                _buildEnergyInfo(
                  'Current Power',
                  '${currentPower.toStringAsFixed(2)} W',
                  Icons.flash_on,
                  Colors.amber[100]!,
                ),
                _buildEnergyInfo(
                  'Total Energy',
                  '${totalEnergy.toStringAsFixed(2)} Wh',
                  Icons.battery_charging_full,
                  Colors.lightGreen[100]!,
                ),
                _buildEnergyInfo(
                  'Estimated Cost',
                  '\$${(totalEnergy * 0.12).toStringAsFixed(2)}',
                  Icons.attach_money,
                  Colors.blue[100]!,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnergyInfo(
      String title, String value, IconData icon, Color iconBg) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.deepOrange[800], size: 24),
          ),
          SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: !_isConnected
          ? Container(
              key: ValueKey('disconnected'),
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.orange[100],
                border: Border.all(color: Colors.orange),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.2),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[800]),
                  SizedBox(width: 8),
                  Text(
                    'Not connected to MongoDB',
                    style: TextStyle(color: Colors.orange[800]),
                  ),
                ],
              ),
            )
          : SizedBox.shrink(key: ValueKey('connected')),
    );
  }

  Widget _buildErrorMessage() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: _errorMessage.isNotEmpty
          ? Container(
              key: ValueKey('error'),
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red[100],
                border: Border.all(color: Colors.red),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.2),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red[800]),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red[800]),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20),
                    color: Colors.red[800],
                    onPressed: () => setState(() {
                      _errorMessage = '';
                    }),
                  ),
                ],
              ),
            )
          : SizedBox.shrink(key: ValueKey('no-error')),
    );
  }

  Widget _buildLightFlow() {
    return AnimatedBuilder(
      animation: _bgFlowController,
      builder: (context, child) {
        return Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              child: Transform.translate(
                offset: Offset(
                  -100 + (_bgFlowAnimation.value * 200),
                  0,
                ),
                child: Container(
                  width: MediaQuery.of(context).size.width * 1.5,
                  height: MediaQuery.of(context).size.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.withOpacity(0.02),
                        Colors.blue.withOpacity(0.05),
                        Colors.blue.withOpacity(0.02),
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient background with 70% opacity
          AnimatedBuilder(
            animation: _gradientController1,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _gradientColor3.value!,
                      _gradientColor4.value!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              );
            },
          ),

          // Light flow animation with improved colors
          AnimatedBuilder(
            animation: _bgFlowController,
            builder: (context, child) {
              return Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(
                        -100 + (_bgFlowAnimation.value * 200),
                        0,
                      ),
                      child: Container(
                        width: MediaQuery.of(context).size.width * 1.5,
                        height: MediaQuery.of(context).size.height,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blueAccent.withOpacity(0.03),
                              Colors.lightBlueAccent.withOpacity(0.08),
                              Colors.blueAccent.withOpacity(0.03),
                            ],
                            stops: [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Semi-transparent overlay for better readability
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.2),
            ),
          ),

          // Main content
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                _buildConnectionStatus(),
                _buildErrorMessage(),
                AnimatedSwitcher(
                  duration: Duration(milliseconds: 500),
                  child: _isLoading
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Column(
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  strokeWidth: 4,
                                ),
                                SizedBox(height: 20),
                                Text(
                                  'Connecting to Neolight...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            _buildModeSelector(),
                            SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  colors: [Colors.blue[700]!, Colors.blue[500]!],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.lightbulb_outline, color: Colors.white),
                                      SizedBox(width: 10),
                                      Text(
                                        'LED Status',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 15),
                                  _buildLedStatus(0),
                                  _buildLedStatus(1),
                                  _buildLedStatus(2),
                                ],
                              ),
                            ),
                            SizedBox(height: 20),
                            _buildBrightnessControl(),
                            SizedBox(height: 20),
                            _buildEnergyMonitor(),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // App bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _gradientController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_gradientColor1.value!, _gradientColor2.value!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: AppBar(
                    title: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Neolight Control',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          left: 0,
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _animationController.value * 0.1,
                                child: Icon(
                                  Icons.lightbulb_outline,
                                  color: Colors.amber,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    centerTitle: true,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    actions: [
                      IconButton(
                        icon: Icon(Icons.refresh, color: Colors.amber),
                        onPressed: _loadFromMongoDB,
                        tooltip: 'Refresh Data',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
