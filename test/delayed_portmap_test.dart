// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// delayed_portmap_test.dart
// Unit tests for delayed port mapping.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class SimpleIntf extends PairInterface {
  SimpleIntf()
      : super(
          portsFromProvider: [
            Logic.port('fp'),
          ],
          portsFromConsumer: [
            Logic.port('fc'),
          ],
        );

  @override
  SimpleIntf clone() => SimpleIntf();
}

class SimpleIntf2 extends PairInterface {
  SimpleIntf2()
      : super(portsFromProvider: [
          Logic.port('fp1', 4),
          Logic.port('fp2', 8),
        ], portsFromConsumer: [
          Logic.port('fc1', 4),
          Logic.port('fc2', 8),
        ], commonInOutPorts: [
          LogicNet.port('cio1', 4),
          LogicNet.port('cio2', 8),
        ]);

  @override
  SimpleIntf2 clone() => SimpleIntf2();
}

BridgeModule leaf(String name, PairRole role) {
  final thisLeaf = BridgeModule(name)
    ..createPort('in1', PortDirection.input)
    ..createPort('out1', PortDirection.output)
    ..addInterface(SimpleIntf(), name: 'myIntf', role: role, connect: false);

  thisLeaf
    ..addPortMap(
        thisLeaf.port('in1'),
        thisLeaf
            .interface('myIntf')
            .port(role == PairRole.consumer ? 'fp' : 'fc'))
    ..addPortMap(
        thisLeaf.port('out1'),
        thisLeaf
            .interface('myIntf')
            .port(role == PairRole.consumer ? 'fc' : 'fp'));

  return thisLeaf;
}

void main() {
  test('interface portmap connected', () async {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);
    final leaf2 = leaf('leaf2', PairRole.provider);

    top
      ..addSubModule(leaf1)
      ..addSubModule(leaf2);
    connectInterfaces(leaf1.interface('myIntf'), leaf2.interface('myIntf'));

    top.pullUpPort(leaf1.createPort('dummy', PortDirection.input));

    await top.build();

    expect(leaf1.interface('myIntf').portMaps.length, 2);
    expect(
        leaf1.interface('myIntf').portMaps.every((e) => e.isConnected), isTrue);

    leaf1.input('in1').put(1);
    expect(leaf2.output('out1').value.toInt(), 1);
    leaf2.input('in1').put(1);
    expect(leaf1.output('out1').value.toInt(), 1);
  });

  test('interface portmap discarded', () async {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);

    top.addSubModule(leaf1);
    connectPorts(top.createPort('in1', PortDirection.input), leaf1.port('in1'));
    connectPorts(
        leaf1.port('out1'), top.createPort('out1', PortDirection.output));

    await top.build();

    expect(leaf1.interface('myIntf').portMaps.length, 2);
    expect(leaf1.interface('myIntf').portMaps.every((e) => !e.isConnected),
        isTrue);

    leaf1.input('in1').put(1);
    expect(top.input('in1').value.toInt(), 1);
    leaf1.output('out1').put(1);
    expect(top.output('out1').value.toInt(), 1);
  });

  test('interface portmap directly', () {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);
    top.addSubModule(leaf1);

    final intf = leaf1.interface('myIntf');
    final pm =
        intf.addPortMap(intf.port('fp'), leaf1.port('in1'), connect: false);

    expect(pm.isConnected, isFalse);

    pm
      ..connect()
      ..connect(); // a second time to test double connect

    expect(pm.isConnected, isTrue);
  });

  test('port mapped interface connected up to simple', () async {
    final top = BridgeModule('top')
      ..createPort('tfp1', PortDirection.output, width: 4)
      ..createPort('tfp2', PortDirection.output, width: 8)
      ..createPort('tfc1', PortDirection.input, width: 4)
      ..createPort('tfc2', PortDirection.input, width: 8)
      ..createPort('tcio1', PortDirection.inOut, width: 4)
      ..createPort('tcio2', PortDirection.inOut, width: 8);

    final leaf = BridgeModule('leaf');
    top
      ..addSubModule(leaf)
      ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

    final leafIntf = leaf.addInterface(SimpleIntf2(),
        name: 'myIntf', role: PairRole.provider);
    final topIntf = top.addInterface(SimpleIntf2(),
        name: 'myIntf', role: PairRole.provider, connect: false);

    // before connection
    topIntf.addPortMap(topIntf.port('fp1'), top.port('tfp1'));

    leafIntf.connectUpTo(topIntf);

    // after connection
    topIntf.addPortMap(topIntf.port('fp2'), top.port('tfp2'));

    await top.build();

    leafIntf.internalInterface!.port('fp1').put(0xa);
    expect(topIntf.interface.port('fp1').value.toInt(), 0xa);

    leafIntf.internalInterface!.port('fp2').put(0x5b);
    expect(topIntf.interface.port('fp2').value.toInt(), 0x5b);

    print(top.generateSynth());
  });

  test('port mapped interface connected up to with slices', () async {
    final top = BridgeModule('top')
      ..createPort('tfp1', PortDirection.output, width: 6)
      ..createPort('tfp2', PortDirection.output, width: 4)
      ..createPort('tfc1', PortDirection.input, width: 6)
      ..createPort('tfc2', PortDirection.input, width: 4)
      ..createPort('tcio1', PortDirection.inOut, width: 6)
      ..createPort('tcio2', PortDirection.inOut, width: 4);

    final leaf = BridgeModule('leaf');
    top
      ..addSubModule(leaf)
      ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

    final leafIntf = leaf.addInterface(SimpleIntf2(),
        name: 'myIntf', role: PairRole.provider);
    final topIntf = top.addInterface(SimpleIntf2(),
        name: 'myIntf', role: PairRole.provider, connect: false);

    topIntf.addPortMap(
        topIntf.port('fp1').slice(2, 1), top.port('tfp1').slice(3, 2));

    leafIntf.connectUpTo(topIntf);

    await top.build();

    print(top.generateSynth());
  });

  //TODO: some tests with actually *delayed* port maps

  test('port mapped interface connected down to', () async {});
}
