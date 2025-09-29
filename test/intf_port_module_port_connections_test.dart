// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intf_port_module_port_connections_test.dart
// Unit tests for connections between ports and intf ports.
//
// 2025 September 29
// Author: Max Korbel <max.korbel@intel.com>

//TODO: what if instead of port map, we make a connection between interface and port!?
// should that just be an error? probably? or maybe it should be external?
// -if a port and interface port are on the same module, in the same direction, it should have been a port map?
// -if they are different directions, then based on the directionality of the connection, we can deduce internal or external

// variables:
// - is port or intf port
// - directionality of port or intf port
// - directionality of connection
// - same module or different module

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/src/bridge_module.dart';
import 'package:rohd_bridge/src/port_direction.dart';
import 'package:rohd_bridge/src/references/references.dart';
import 'package:rohd_bridge/src/rohd_bridge_exception.dart';
import 'package:test/test.dart';

class _PortTestCase {
  final bool isIntfPort;
  final PortDirection direction;

  // ignore: avoid_positional_boolean_parameters
  const _PortTestCase(this.isIntfPort, this.direction);

  @override
  String toString() => '${direction.name} ${isIntfPort ? 'intf port' : 'port'}';
}

class _PortConnectionTestCase {
  final _PortTestCase src;
  final _PortTestCase dst;
  final bool onSameModule;

  // ignore: avoid_positional_boolean_parameters
  const _PortConnectionTestCase(this.src, this.dst, this.onSameModule);

  @override
  String toString() =>
      '${onSameModule ? 'on same module' : 'on diff modules'}  $src -> $dst ';
}

class TestIntf extends PairInterface {
  final bool isIo;
  TestIntf({required this.isIo})
      : super(portsFromProvider: [
          if (!isIo) Logic.port('testPort', 8),
        ], commonInOutPorts: [
          if (isIo) LogicNet.port('testPort', 8)
        ]);

  @override
  TestIntf clone() => TestIntf(isIo: isIo);
}

void main() {
  group('port intf port connections', () {
    final portTestCases = [
      for (final isIntfPort in [true, false])
        for (final direction in PortDirection.values)
          _PortTestCase(isIntfPort, direction)
    ];

    final portConnectionTestCases = [
      for (final src in portTestCases)
        for (final dst in portTestCases)
          for (final onSameModule in [true, false])
            if ((src.direction == PortDirection.inOut) ==
                (dst.direction == PortDirection.inOut))
              _PortConnectionTestCase(src, dst, onSameModule)
    ];

    final connectApis = [
      (
        'connectPorts',
        (PortReference src, PortReference dst) => connectPorts(src, dst)
      ),
      ('gets', (PortReference src, PortReference dst) => dst.gets(src)),
    ];

    for (final connectApi in connectApis) {
      group('using ${connectApi.$1}', () {
        for (final testCase in portConnectionTestCases) {
          test(testCase.toString(), () async {
            final srcMod = BridgeModule('modA');
            final dstMod =
                testCase.onSameModule ? srcMod : BridgeModule('modB');

            final top = BridgeModule('top')
              ..addSubModule(srcMod)
              ..pullUpPort(srcMod.createPort('dummy', PortDirection.input));

            if (!testCase.onSameModule) {
              top.addSubModule(dstMod);
            }

            final srcPort =
                srcMod.createPort('src', testCase.src.direction, width: 8);
            final dstPort =
                dstMod.createPort('dst', testCase.dst.direction, width: 8);

            var srcPortRef = srcPort;
            var dstPortRef = dstPort;

            var expectFailure = false;

            if (!testCase.onSameModule &&
                testCase.src.direction == testCase.dst.direction) {
              // this is like a pass-through, not yet supported
              expectFailure = true;
            }

            try {
              if (testCase.src.isIntfPort) {
                final srcIntf = srcMod.addInterface(
                    TestIntf(
                        isIo: testCase.src.direction == PortDirection.inOut),
                    name: 'testIntfA',
                    role: srcPort.direction == PortDirection.input
                        ? PairRole.consumer
                        : PairRole.provider,
                    connect: false);

                srcMod.addPortMap(srcPort, srcIntf.port('testPort'),
                    connect: true);

                srcPortRef = srcIntf.port('testPort');
              }

              if (testCase.dst.isIntfPort) {
                final dstIntf = dstMod.addInterface(
                    TestIntf(
                        isIo: testCase.dst.direction == PortDirection.inOut),
                    name: 'testIntfB',
                    role: dstPort.direction == PortDirection.output
                        ? PairRole.provider
                        : PairRole.consumer,
                    connect: false);

                dstMod.addPortMap(dstPort, dstIntf.port('testPort'),
                    connect: true);

                dstPortRef = dstIntf.port('testPort');
              }

              connectApi.$2(srcPortRef, dstPortRef);

              await top.build();

              final val = LogicValue.of(0x45, width: 8);
              srcPort.port.put(val);
              expect(dstPort.port.value, equals(val));

              // print(top.generateSynth());

              if (expectFailure) {
                fail('Expected failure but connection succeeded');
              }
            } on RohdBridgeException catch (e) {
              // we only catch RohdBridgeException! make sure good err messages!

              if (!expectFailure) {
                // rethrow; //TODO?
                fail('Unexpected failure: $e');
              }
            }
          });
        }
      });
    }
  });
}
