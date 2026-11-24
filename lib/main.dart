import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/painting.dart' show GradientRotation;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ======================================================
// ESP32 BLE UUID (เดิม)
// ======================================================

final Guid serviceUuid = Guid(
  "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
);

final Guid characteristicUuid = Guid(
  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
);

// ======================================================
// MAIN
// ======================================================

void main() {
  runApp(const MotorApp());
}

// ======================================================
// APP
// ======================================================

class MotorApp extends StatelessWidget {
  const MotorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Wolffia RGB Harvester",
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080812),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const MotorHomePage(),
    );
  }
}

// ======================================================
// HOME PAGE
// ======================================================

class MotorHomePage extends StatefulWidget {
  const MotorHomePage({super.key});

  @override
  State<MotorHomePage> createState() =>
      _MotorHomePageState();
}

// ======================================================
// STATE
// ======================================================

class _MotorHomePageState extends State<MotorHomePage>
    with SingleTickerProviderStateMixin {

  BluetoothDevice? esp32;

  BluetoothCharacteristic? motorCharacteristic;

  bool isConnected = false;
  bool isScanning = false;

  String statusText = "ยังไม่ได้เชื่อมต่อ";

  List<ScanResult> scanResults = [];

  StreamSubscription<List<ScanResult>>? scanSubscription;

  StreamSubscription<BluetoothConnectionState>?
      connectionSubscription;

  // ความเร็วใบพัด M1 + M2
  int propellerSpeed = 150;

  // ความเร็วสายพาน M3
  int beltSpeed = 150;

  // RGB animation
  late AnimationController _rgbController;

  // ====================================================
  // START
  // ====================================================

  @override
  void initState() {
    super.initState();

    _rgbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    checkBluetooth();
  }

  // ====================================================
  // CHECK BLUETOOTH
  // ====================================================

  Future<void> checkBluetooth() async {
    try {
      final state =
          await FlutterBluePlus.adapterState.first;

      if (!mounted) return;

      setState(() {
        statusText =
            state == BluetoothAdapterState.on
                ? "Bluetooth พร้อมใช้งาน"
                : "กรุณาเปิด Bluetooth";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusText = "ตรวจสอบ Bluetooth ไม่สำเร็จ";
      });
    }
  }

  // ====================================================
  // SCAN ESP32
  // ====================================================

  Future<void> scanForESP32() async {

    if (isScanning) return;

    final bluetoothState =
        await FlutterBluePlus.adapterState.first;

    if (bluetoothState != BluetoothAdapterState.on) {
      setState(() {
        statusText = "กรุณาเปิด Bluetooth ก่อน";
      });
      return;
    }

    setState(() {
      isScanning = true;
      scanResults.clear();
      statusText = "กำลังค้นหา ESP32...";
    });

    await scanSubscription?.cancel();

    scanSubscription =
        FlutterBluePlus.scanResults.listen((results) {

      if (!mounted) return;

      setState(() {
        scanResults = results;
      });
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          statusText = "สแกนไม่สำเร็จ: $e";
        });
      }
    }

    if (mounted) {
      setState(() {
        isScanning = false;
      });
    }
  }

  // ====================================================
  // CONNECT ESP32
  // ====================================================

  Future<void> connectToESP32(
      BluetoothDevice device) async {

    try {
      setState(() {
        statusText = "กำลังเชื่อมต่อ...";
      });

      await FlutterBluePlus.stopScan();

      await device.connect(
        timeout: const Duration(seconds: 15),
      );

      esp32 = device;

      await connectionSubscription?.cancel();

      connectionSubscription =
          device.connectionState.listen((state) {

        if (!mounted) return;

        if (state ==
            BluetoothConnectionState.connected) {

          setState(() {
            isConnected = true;
            statusText = "เชื่อมต่อ ESP32 แล้ว";
          });
        }

        if (state ==
            BluetoothConnectionState.disconnected) {

          setState(() {
            isConnected = false;
            motorCharacteristic = null;
            statusText =
                "Bluetooth ถูกตัดการเชื่อมต่อ";
          });
        }
      });

      // ค้นหา BLE Service
      final services = await device.discoverServices();

      BluetoothCharacteristic? foundCharacteristic;

      for (final service in services) {

        if (service.uuid == serviceUuid) {

          for (final characteristic
              in service.characteristics) {

            if (characteristic.uuid ==
                characteristicUuid) {

              foundCharacteristic = characteristic;
              break;
            }
          }
        }
      }

      if (foundCharacteristic == null) {

        setState(() {
          statusText = "ไม่พบ Motor Characteristic";
          isConnected = false;
        });

        await device.disconnect();
        return;
      }

      motorCharacteristic = foundCharacteristic;

      setState(() {
        isConnected = true;
        statusText = "เชื่อมต่อ ESP32 สำเร็จ";
      });

    } catch (e) {

      if (mounted) {
        setState(() {
          isConnected = false;
          motorCharacteristic = null;
          statusText = "เชื่อมต่อไม่สำเร็จ";
        });
      }

      debugPrint("CONNECT ERROR: $e");
    }
  }

  // ====================================================
  // SEND COMMAND
  // ====================================================

  Future<void> sendCommand(String command) async {

    if (!isConnected ||
        motorCharacteristic == null) {

      if (mounted) {
        setState(() {
          statusText = "ยังไม่ได้เชื่อมต่อ ESP32";
        });
      }

      return;
    }

    try {

      await motorCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      if (mounted) {
        setState(() {
          statusText = "ส่งคำสั่ง: $command";
        });
      }

    } catch (e) {

      if (mounted) {
        setState(() {
          statusText = "ส่งคำสั่งไม่สำเร็จ";
        });
      }

      debugPrint("WRITE ERROR: $e");
    }
  }

  // ====================================================
  // SEND SPEED
  // ====================================================

  Future<void> sendSpeedCommand(
      String type, int speed) async {

    if (!isConnected ||
        motorCharacteristic == null) {

      if (mounted) {
        setState(() {
          statusText = "ยังไม่ได้เชื่อมต่อ ESP32";
        });
      }

      return;
    }

    try {

      // P = ใบพัด M1 + M2
      // T = สายพาน M3

      final command = "$type$speed";

      await motorCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      if (mounted) {
        setState(() {
          statusText = "ปรับความเร็ว: $command";
        });
      }

    } catch (e) {

      if (mounted) {
        setState(() {
          statusText = "ส่งค่าความเร็วไม่สำเร็จ";
        });
      }

      debugPrint("SPEED ERROR: $e");
    }
  }

  // ====================================================
  // DISCONNECT
  // ====================================================

  Future<void> disconnectESP32() async {

    try {

      // หยุดใบพัดและสายพานก่อนตัดการเชื่อมต่อ

      await sendCommand("S");
      await sendCommand("X");

      await esp32?.disconnect();

    } catch (e) {
      debugPrint("DISCONNECT ERROR: $e");
    }

    if (mounted) {
      setState(() {
        isConnected = false;
        esp32 = null;
        motorCharacteristic = null;
        statusText = "ตัดการเชื่อมต่อแล้ว";
      });
    }
  }

  // ====================================================
  // RGB PANEL
  // ====================================================

  Widget rgbPanel({
    required Widget child,
    double radius = 18,
  }) {

    return AnimatedBuilder(
      animation: _rgbController,
      builder: (context, _) {

        return Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: SweepGradient(
              transform: GradientRotation(
                _rgbController.value * 2 * math.pi,
              ),
              colors: const [
                Colors.red,
                Colors.orange,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.pink,
                Colors.red,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.20),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF10101D),
              borderRadius: BorderRadius.circular(
                radius - 2,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  // ====================================================
  // NEON SECTION
  // ====================================================

  Widget sectionTitle(String title, IconData icon) {

    return Row(
      children: [
        Icon(
          icon,
          color: Colors.cyanAccent,
          size: 23,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ====================================================
  // MOTOR BUTTON
  // ====================================================

  Widget motorButton({
    required IconData icon,
    required String text,
    required String command,
    double size = 90,
    Color color = Colors.cyan,
  }) {

    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: () {
          sendCommand(command);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF19192A),
          foregroundColor: color,
          elevation: 8,
          shadowColor: color.withValues(alpha: 0.5),
          shape: CircleBorder(
            side: BorderSide(
              color: color,
              width: 1.5,
            ),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 35),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================================================
  // STOP BUTTON
  // ====================================================

  Widget stopButton() {

    return SizedBox(
      width: 90,
      height: 90,
      child: ElevatedButton(
        onPressed: () {
          sendCommand("S");
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF35101D),
          foregroundColor: Colors.redAccent,
          elevation: 10,
          shadowColor: Colors.red,
          shape: const CircleBorder(
            side: BorderSide(
              color: Colors.redAccent,
              width: 2,
            ),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop, size: 38),
            Text(
              "หยุด",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================================================
  // SPEED SLIDER
  // ====================================================

  Widget speedSlider({
    required String title,
    required String subtitle,
    required int speed,
    required Color color,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171725),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withValues(alpha: 0.65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [

              const Text(
                "ความเร็วปัจจุบัน",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [

                  Text(
                    "$speed",
                    style: TextStyle(
                      color: color,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.only(
                      bottom: 5,
                      left: 4,
                    ),
                    child: Text(
                      "/ 250",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: Colors.white12,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 9,
              ),
            ),
            child: Slider(
              min: 0,
              max: 250,
              divisions: 250,
              value: speed.toDouble(),
              label: "$speed",
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),

          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "0",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              Text(
                "125",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              Text(
                "250",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ====================================================
  // BUILD
  // ====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF080812),

      appBar: AppBar(
        backgroundColor: const Color(0xFF080812),
        centerTitle: true,
        title: const Text(
          "WOLFFIA RGB",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),

      body: SafeArea(

        child: AnimatedBuilder(
          animation: _rgbController,
          builder: (context, _) {

            return Container(

              margin: const EdgeInsets.fromLTRB(
                8, 5, 8, 8,
              ),

              padding: const EdgeInsets.all(2.5),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: SweepGradient(
                  transform: GradientRotation(
                    _rgbController.value * 2 * math.pi,
                  ),
                  colors: const [
                    Colors.red,
                    Colors.orange,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.pink,
                    Colors.red,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withValues(alpha: 0.12),
                    blurRadius: 15,
                  ),
                ],
              ),

              child: Container(

                decoration: BoxDecoration(
                  color: const Color(0xFF0C0C17),
                  borderRadius: BorderRadius.circular(20),
                ),

                child: SingleChildScrollView(

                  padding: const EdgeInsets.all(12),

                  child: Column(
                    children: [

                      // --------------------------------
                      // HEADER
                      // --------------------------------

                      const Text(
                        "SMART HARVESTER CONTROL",
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 15),

                      // --------------------------------
                      // STATUS
                      // --------------------------------

                      rgbPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            children: [

                              Icon(
                                isConnected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_disabled,
                                size: 38,
                                color: isConnected
                                    ? Colors.greenAccent
                                    : Colors.grey,
                              ),

                              const SizedBox(height: 8),

                              Text(
                                statusText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isConnected
                                      ? Colors.greenAccent
                                      : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // --------------------------------
                      // CONNECT
                      // --------------------------------

                      Row(
                        children: [

                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isScanning
                                  ? null
                                  : scanForESP32,
                              icon: const Icon(
                                Icons.search,
                              ),
                              label: Text(
                                isScanning
                                    ? "กำลังค้นหา..."
                                    : "ค้นหา ESP32",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF172B42),
                                foregroundColor:
                                    Colors.cyanAccent,
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isConnected
                                  ? disconnectESP32
                                  : null,
                              icon: const Icon(
                                Icons.bluetooth_disabled,
                              ),
                              label: const Text(
                                "ตัดการเชื่อมต่อ",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF351522),
                                foregroundColor:
                                    Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // --------------------------------
                      // DEVICE LIST
                      // --------------------------------

                      if (scanResults.isNotEmpty)

                        Container(
                          constraints:
                              const BoxConstraints(
                            maxHeight: 150,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: scanResults.length,
                            itemBuilder: (context, index) {

                              final result =
                                  scanResults[index];

                              final device = result.device;

                              final name =
                                  device.platformName;

                              if (name.isEmpty) {
                                return const SizedBox();
                              }

                              return ListTile(
                                leading: const Icon(
                                  Icons.bluetooth,
                                  color: Colors.cyanAccent,
                                ),
                                title: Text(name),
                                subtitle: Text(
                                  device.remoteId.str,
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    connectToESP32(device);
                                  },
                                  child: const Text(
                                    "เชื่อมต่อ",
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 20),

                      // --------------------------------
                      // PROPELLER CONTROL
                      // --------------------------------

                      rgbPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [

                              sectionTitle(
                                "มอเตอร์ใบพัด",
                                Icons.air,
                              ),

                              const SizedBox(height: 5),

                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "PROPELLER M1 + M2",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Forward

                              motorButton(
                                icon: Icons.keyboard_arrow_up,
                                text: "เดินหน้า",
                                command: "F",
                              ),

                              const SizedBox(height: 15),

                              // Left Stop Right

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [

                                  motorButton(
                                    icon:
                                        Icons.keyboard_arrow_left,
                                    text: "ซ้าย",
                                    command: "R",
                                  ),

                                  const SizedBox(width: 12),

                                  stopButton(),

                                  const SizedBox(width: 12),

                                  motorButton(
                                    icon:
                                        Icons.keyboard_arrow_right,
                                    text: "ขวา",
                                    command: "L",
                                  ),
                                ],
                              ),

                              const SizedBox(height: 15),

                              // Backward

                              motorButton(
                                icon: Icons.keyboard_arrow_down,
                                text: "ถอยหลัง",
                                command: "B",
                              ),

                              const SizedBox(height: 20),

                              // Propeller speed slider

                              speedSlider(
                                title: "PROPELLER SPEED",
                                subtitle:
                                    "ปรับความเร็วใบพัด M1 และ M2 พร้อมกัน",
                                speed: propellerSpeed,
                                color: Colors.cyanAccent,

                                onChanged: (value) {
                                  setState(() {
                                    propellerSpeed =
                                        value.round();
                                  });
                                },

                                onChangeEnd: (value) {
                                  sendSpeedCommand(
                                    "P",
                                    value.round(),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --------------------------------
                      // BELT CONTROL
                      // --------------------------------

                      rgbPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [

                              sectionTitle(
                                "มอเตอร์สายพาน",
                                Icons.conveyor_belt,
                              ),

                              const SizedBox(height: 5),

                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "CONVEYOR BELT M3",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              Row(
                                children: [

                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        sendCommand("V");
                                      },
                                      icon: const Icon(
                                        Icons.play_arrow,
                                      ),
                                      label: const Text(
                                        "เปิดสายพาน",
                                      ),
                                      style:
                                          ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF123D2B),
                                        foregroundColor:
                                            Colors.greenAccent,
                                        padding:
                                            const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        side: const BorderSide(
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        sendCommand("X");
                                      },
                                      icon: const Icon(
                                        Icons.stop,
                                      ),
                                      label: const Text(
                                        "ปิดสายพาน",
                                      ),
                                      style:
                                          ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF3A1421),
                                        foregroundColor:
                                            Colors.redAccent,
                                        padding:
                                            const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        side: const BorderSide(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // Belt speed slider

                              speedSlider(
                                title: "CONVEYOR SPEED",
                                subtitle:
                                    "ปรับความเร็วสายพาน M3 แยกอิสระ",
                                speed: beltSpeed,
                                color: Colors.greenAccent,

                                onChanged: (value) {
                                  setState(() {
                                    beltSpeed =
                                        value.round();
                                  });
                                },

                                onChangeEnd: (value) {
                                  sendSpeedCommand(
                                    "T",
                                    value.round(),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --------------------------------
                      // FOOTER
                      // --------------------------------

                      const Text(
                        "WOLFFIA HARVESTER SYSTEM",
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "RGB GAMING CONTROL INTERFACE",
                        style: TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 9,
                          letterSpacing: 1.5,
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ====================================================
  // DISPOSE
  // ====================================================

  @override
  void dispose() {

    _rgbController.dispose();

    scanSubscription?.cancel();

    connectionSubscription?.cancel();

    super.dispose();
  }
}
