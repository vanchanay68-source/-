import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


// ======================================================
// ESP32 BLE UUID
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

      title: "ESP32 Motor Control",

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
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
  State<MotorHomePage> createState() => _MotorHomePageState();
}


// ======================================================
// STATE
// ======================================================

class _MotorHomePageState extends State<MotorHomePage> {

  BluetoothDevice? esp32;

  BluetoothCharacteristic? motorCharacteristic;

  bool isConnected = false;

  bool isScanning = false;

  String statusText = "ยังไม่ได้เชื่อมต่อ";

  List<ScanResult> scanResults = [];

  StreamSubscription<List<ScanResult>>? scanSubscription;

  StreamSubscription<BluetoothConnectionState>?
      connectionSubscription;


  // ====================================================
  // START
  // ====================================================

  @override
  void initState() {
    super.initState();

    checkBluetooth();
  }


  // ====================================================
  // CHECK BLUETOOTH
  // ====================================================

  Future<void> checkBluetooth() async {

    try {

      BluetoothAdapterState state =
          await FlutterBluePlus.adapterState.first;

      if (state != BluetoothAdapterState.on) {

        setState(() {
          statusText = "กรุณาเปิด Bluetooth";
        });

      } else {

        setState(() {
          statusText = "Bluetooth พร้อมใช้งาน";
        });

      }

    } catch (e) {

      setState(() {
        statusText = "ตรวจสอบ Bluetooth ไม่สำเร็จ";
      });

    }
  }


  // ====================================================
  // SCAN
  // ====================================================

  Future<void> scanForESP32() async {

    if (isScanning) {
      return;
    }


    // ตรวจสอบ Bluetooth ก่อน

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


    scanSubscription?.cancel();


    scanSubscription =
        FlutterBluePlus.scanResults.listen((results) {

      if (!mounted) {
        return;
      }

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

          statusText =
              "สแกนไม่สำเร็จ: $e";

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


      // หยุด Scan ก่อนเชื่อมต่อ

      await FlutterBluePlus.stopScan();


      // เชื่อมต่อ

      await device.connect(
        timeout: const Duration(seconds: 15),
      );


      esp32 = device;


      // ตรวจสอบสถานะการเชื่อมต่อ

      connectionSubscription?.cancel();

      connectionSubscription =
          device.connectionState.listen((state) async {

        if (!mounted) {
          return;
        }


        if (state == BluetoothConnectionState.connected) {

          setState(() {

            isConnected = true;

            statusText = "เชื่อมต่อ ESP32 แล้ว";

          });

        }


        if (state == BluetoothConnectionState.disconnected) {

          setState(() {

            isConnected = false;

            motorCharacteristic = null;

            statusText = "Bluetooth ถูกตัดการเชื่อมต่อ";

          });

        }

      });


      // สำคัญ:
      // ต้องค้นหา Service หลังเชื่อมต่อ

      List<BluetoothService> services =
          await device.discoverServices();


      BluetoothCharacteristic? foundCharacteristic;


      for (BluetoothService service in services) {

        if (service.uuid == serviceUuid) {

          for (BluetoothCharacteristic characteristic
              in service.characteristics) {

            if (characteristic.uuid ==
                characteristicUuid) {

              foundCharacteristic =
                  characteristic;

              break;
            }
          }
        }
      }


      if (foundCharacteristic == null) {

        setState(() {

          statusText =
              "ไม่พบ Motor Characteristic";

          isConnected = false;

        });

        return;
      }


      motorCharacteristic =
          foundCharacteristic;


      setState(() {

        isConnected = true;

        statusText =
            "เชื่อมต่อ ESP32 สำเร็จ";

      });


    } catch (e) {

      setState(() {

        isConnected = false;

        statusText =
            "เชื่อมต่อไม่สำเร็จ";

      });

      debugPrint("CONNECT ERROR: $e");

    }
  }


  // ====================================================
  // SEND COMMAND
  // ====================================================

  Future<void> sendCommand(String command) async {

    if (!isConnected ||
        motorCharacteristic == null) {

      setState(() {

        statusText =
            "ยังไม่ได้เชื่อมต่อ ESP32";

      });

      return;
    }


    try {

      await motorCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );


      setState(() {

        statusText =
            "ส่งคำสั่ง: $command";

      });


    } catch (e) {

      setState(() {

        statusText =
            "ส่งคำสั่งไม่สำเร็จ";

      });

      debugPrint("WRITE ERROR: $e");

    }
  }


  // ====================================================
  // DISCONNECT
  // ====================================================

  Future<void> disconnectESP32() async {

    try {

      // หยุดมอเตอร์ก่อน

      await sendCommand("S");

      await esp32?.disconnect();

    } catch (e) {

      debugPrint("DISCONNECT ERROR: $e");

    }


    if (mounted) {

      setState(() {

        isConnected = false;

        esp32 = null;

        motorCharacteristic = null;

        statusText =
            "ตัดการเชื่อมต่อแล้ว";

      });

    }
  }


  // ====================================================
  // MOTOR BUTTON
  // ====================================================

  Widget motorButton({

    required IconData icon,

    required String text,

    required String command,

    double size = 90,

  }) {

    return SizedBox(

      width: size,

      height: size,

      child: ElevatedButton(

        onPressed: () {

          sendCommand(command);

        },

        style: ElevatedButton.styleFrom(

          shape: const CircleBorder(),

          padding: EdgeInsets.zero,

        ),

        child: Column(

          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            Icon(
              icon,
              size: 35,
            ),

            const SizedBox(height: 4),

            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
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

          backgroundColor: Colors.red,

          foregroundColor: Colors.white,

          shape: const CircleBorder(),

        ),

        child: const Column(

          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            Icon(
              Icons.stop,
              size: 38,
            ),

            Text(
              "หยุด",
              style: TextStyle(
                fontSize: 12,
              ),
            ),

          ],
        ),
      ),
    );
  }


  // ====================================================
  // BUILD
  // ====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text(
          "ESP32 Motor Control",
        ),

        centerTitle: true,

      ),


      body: SafeArea(

        child: Column(

          children: [

            const SizedBox(height: 15),


            // ------------------------------------------
            // STATUS
            // ------------------------------------------

            Container(

              margin:
                  const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),

              padding:
                  const EdgeInsets.all(15),

              width: double.infinity,

              decoration: BoxDecoration(

                borderRadius:
                    BorderRadius.circular(15),

                color: isConnected
                    ? Colors.green.shade100
                    : Colors.grey.shade200,

              ),

              child: Column(

                children: [

                  Icon(

                    isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,

                    size: 40,

                    color: isConnected
                        ? Colors.green
                        : Colors.grey,

                  ),

                  const SizedBox(height: 8),

                  Text(

                    statusText,

                    textAlign:
                        TextAlign.center,

                    style: const TextStyle(

                      fontSize: 17,

                      fontWeight:
                          FontWeight.bold,

                    ),

                  ),

                ],
              ),
            ),


            const SizedBox(height: 15),


            // ------------------------------------------
            // CONNECT BUTTON
            // ------------------------------------------

            Padding(

              padding:
                  const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),

              child: Row(

                children: [

                  Expanded(

                    child: ElevatedButton.icon(

                      onPressed:
                          isScanning
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

                    ),
                  ),


                  const SizedBox(width: 10),


                  Expanded(

                    child: ElevatedButton.icon(

                      onPressed:
                          isConnected
                              ? disconnectESP32
                              : null,

                      icon: const Icon(
                        Icons.bluetooth_disabled,
                      ),

                      label: const Text(
                        "ตัดการเชื่อมต่อ",
                      ),

                    ),
                  ),

                ],
              ),
            ),


            const SizedBox(height: 10),


            // ------------------------------------------
            // DEVICE LIST
            // ------------------------------------------

            if (scanResults.isNotEmpty)

              SizedBox(

                height: 100,

                child: ListView.builder(

                  itemCount:
                      scanResults.length,

                  itemBuilder:
                      (context, index) {

                    final result =
                        scanResults[index];

                    final device =
                        result.device;

                    final name =
                        device.platformName;

                    if (name.isEmpty) {

                      return const SizedBox();

                    }


                    return ListTile(

                      leading:
                          const Icon(
                            Icons.bluetooth,
                          ),

                      title: Text(name),

                      subtitle: Text(
                        device.remoteId.str,
                      ),

                      trailing:
                          ElevatedButton(

                        onPressed: () {

                          connectToESP32(
                            device,
                          );

                        },

                        child:
                            const Text(
                              "เชื่อมต่อ",
                            ),

                      ),
                    );
                  },
                ),
              ),


            const Spacer(),


            // ------------------------------------------
            // MOTOR CONTROL
            // ------------------------------------------

            const Text(

              "ควบคุมมอเตอร์",

              style: TextStyle(

                fontSize: 22,

                fontWeight:
                    FontWeight.bold,

              ),
            ),


            const SizedBox(height: 20),


            // เดินหน้า

            motorButton(

              icon:
                  Icons.keyboard_arrow_up,

              text:
                  "เดินหน้า",

              command:
                  "F",

            ),


            const SizedBox(height: 15),


            // ซ้าย - หยุด - ขวา

            Row(

              mainAxisAlignment:
                  MainAxisAlignment.center,

              children: [

                motorButton(

                  icon:
                      Icons.keyboard_arrow_left,

                  text:
                      "ซ้าย",

                  command:
                      "L",

                ),


                const SizedBox(width: 15),


                stopButton(),


                const SizedBox(width: 15),


                motorButton(

                  icon:
                      Icons.keyboard_arrow_right,

                  text:
                      "ขวา",

                  command:
                      "R",

                ),

              ],
            ),


            const SizedBox(height: 15),


            // ถอยหลัง

            motorButton(

              icon:
                  Icons.keyboard_arrow_down,

              text:
                  "ถอยหลัง",

              command:
                  "B",

            ),


            const SizedBox(height: 30),

          ],
        ),
      ),
    );
  }


  // ====================================================
  // DISPOSE
  // ====================================================

  @override
  void dispose() {

    scanSubscription?.cancel();

    connectionSubscription?.cancel();

    super.dispose();

  }
}
