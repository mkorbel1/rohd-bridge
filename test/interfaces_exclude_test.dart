// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interfaces_exclude_test.dart
// Unit tests for exclusion functionality while connecting interfaces.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class IntfA extends PairInterface {
  final int paramA;

  IntfA({this.paramA = 1}) : super() {
    setPorts([Logic.port('fc', paramA)], [PairDirection.fromConsumer]);
    setPorts([Logic.port('fp', paramA)], [PairDirection.fromProvider]);
    setPorts([Logic.port('apple', 4)], [PairDirection.fromProvider]);
    setPorts([Logic.port('orange', 4)], [PairDirection.fromConsumer]);
  }

  @override
  IntfA clone() => IntfA(paramA: paramA);
}

class LM1 extends BridgeModule {
  late int paramA;
  LM1({this.paramA = 8, String instName = 'lm1'})
      : super('lm1', name: instName, reserveDefinitionName: false) {
    final inf1 = addInterface(
      IntfA(paramA: paramA),
      name: 'intf1',
      role: PairRole.consumer,
      connect: false,
    );

    addOutput('orange', width: 4);

    addPortMap(port('orange'), inf1.port('orange'));

    addInput('apple', Logic(name: 'apple', width: 4), width: 4);
    addPortMap(port('apple'), inf1.port('apple'));

    addOutputArray('out1', dimensions: [5, 1]);

    addOutput('fc', width: 8);
    addPortMap(port('fc'), inf1.port('fc'));
  }
}

class LM2 extends BridgeModule {
  late int paramA;
  LM2({this.paramA = 8, String instName = 'lm2'})
      : super('lm2', name: instName, reserveDefinitionName: false) {
    final inf1 = addInterface(
      IntfA(paramA: paramA),
      name: 'intf1',
      role: PairRole.provider,
      connect: false,
    );

    addOutput('dummy', width: 8);

    addOutput('apple', width: 4);

    addPortMap(port('apple'), inf1.port('apple'));

    addInput('orange', Logic(name: 'orange', width: 4), width: 4);
    addPortMap(port('orange'), inf1.port('orange'));

    addOutput('out1', width: 8);
    addPortMap(port('out1'), inf1.port('fp'));
  }
}

void main() {
  test('exclusive excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'),
        exceptPorts: {'apple', 'fc', 'fp'});
    top.pullUpPort(lm2Inst.port('dummy'));
    await top.build();
    expect(par1.inputs.containsKey('intf1_apple'), false);
    expect(par2.outputs.containsKey('intf1_apple'), false);
  });

  test('incomplete excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    try {
      connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'),
          exceptPorts: {'apple', 'fc'});
      top.pullUpPort(lm2Inst.port('dummy'));
      await top.build();
      expect(par1.inputs.containsKey('intf1_apple'), false);
      expect(par2.outputs.containsKey('intf1_apple'), false);
    } on Exception catch (e) {
      expect(
          e.toString(),
          contains('Cannot connect interface intf1'
              ' at lm2 to interface intf1 at lm1'
              ' because there are unmapped ports :'
              ' {fp} on receiver'));
    }
  });

  test('default excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    try {
      connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'));
      top.pullUpPort(lm2Inst.port('dummy'));
      await top.build();
      expect(par1.outputs.length + par1.inputs.length + par1.inOuts.length,
          lm1Inst.interface('intf1').interface.ports.length);
      //Excluding the dummy port in calculation below
      expect(par2.outputs.length + par2.inputs.length + par2.inOuts.length - 1,
          lm2Inst.interface('intf1').interface.ports.length);
    } on Exception catch (e) {
      expect(
          e.toString(),
          contains('Cannot connect interface intf1'
              ' at lm2 to interface intf1 at lm1 because'
              ' there are unmapped ports :'
              ' {fc} on driver : {fp} on receiver'));
    }
  });

  //Test plan:
  // - BridgeModule.pullUpInterface
  //   -> passes correctly to connectUpTo, punchUpTo
  // - connectInterfaces
  //   -> passes correctly to pullUpInterface, _pullUpInterfaceAndConnect
  // - InterfaceReference
  //   - punchUpTo
  //     -> _connectAllPortMaps, cloneExcept, connectUpTo
  //   - punchDownTo
  //     -> _connectAllPortMaps, cloneExcept, connectDownTo
  //   - connectUpTo
  //     -> _connectAllPortMaps (both), receive and drive other (both)
  //   - connectDownTo
  //     -> _connectAllPortMaps (both), receive and drive other (both)
  //   - connectTo
  //     -> _connectAllPortMaps (both), receive and drive other (both)

  test('pullUpInterface with exceptPorts', () async {
    final top = BridgeModule('top');
    final leaf = LM1();
    final mid = BridgeModule('mid')..addSubModule(leaf);
    top
      ..addSubModule(mid)
      ..pullUpInterface(leaf.interface('intf1'),
          exceptPorts: {'orange', 'apple'});

    await top.build();

    expect(top.hasPortWithSubstring('apple'), isFalse);
    expect(top.hasPortWithSubstring('orange'), isFalse);
    expect(mid.hasPortWithSubstring('apple'), isFalse);
    expect(mid.hasPortWithSubstring('orange'), isFalse);
  });
}

extension on BridgeModule {
  /// Indicates if any port in this module contains [subName] as a substring.
  bool hasPortWithSubstring(String subName) =>
      inputs.keys.any((element) => element.contains(subName)) ||
      outputs.keys.any((element) => element.contains(subName)) ||
      inOuts.keys.any((element) => element.contains(subName));
}
