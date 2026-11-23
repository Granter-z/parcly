import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/ui/screens/pdd/pdd_clean_ui_script.dart';

void main() {
  test('商城清理脚本不回读布局，只处理新增节点', () async {
    final node = await Process.run('sh', ['-c', 'command -v node']);
    if (node.exitCode != 0) {
      markTestSkipped('未安装 Node，跳过 JS 行为测试');
      return;
    }
    const script = pddCleanUiScript;
    expect(script, isNot(contains('innerText')));
    expect(script, isNot(contains('querySelectorAll')));
    expect(script, contains('addedNodes'));
    expect(script, contains('observer.observe(document.body'));
    expect(script, isNot(contains('observe(document.documentElement')));
    expect(script, contains('if (window.__pddCleanInstalled) return;'));
    expect(script, contains('__pddBadgeChecked'));

    const harness = r'''
class Style { setProperty(k, v) { this[k] = v; } }
class El {
  constructor(text, position = 'static') {
    this.nodeType = 1; this.style = new Style(); this.position = position;
    this.parentElement = null; this.textContent = text;
  }
}
const hidden = new El('在App打开', 'fixed');
const text = {nodeType: 3, nodeValue: '在App打开', parentElement: hidden};
hidden.parentElement = {nodeType: 1, parentElement: null};
global.window = {getComputedStyle: e => ({position: e.position})};
global.document = {
  head: {appendChild() {}},
  createElement: () => new El(''),
  createTreeWalker: () => ({nextNode: () => null}),
  body: new El(''),
};
global.Node = {TEXT_NODE: 3, ELEMENT_NODE: 1};
global.NodeFilter = {SHOW_TEXT: 4};
global.requestAnimationFrame = f => f();
global.MutationObserver = class {
  constructor(f) { this.f = f; }
  observe() { this.f([{type: 'childList', addedNodes: [text]}]); }
};
''';
    const assertion = r'''
if (hidden.style.display !== 'none') throw new Error('动态浮标未隐藏');
if (global.window.__pddCleanObserver == null) throw new Error('未安装增量观察器');
''';
    final result =
        await Process.run('node', ['-e', harness + script + assertion]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final repeated = await Process.run(
        'node', ['-e', harness + script + script + assertion]);
    expect(repeated.exitCode, 0,
        reason: '${repeated.stdout}${repeated.stderr}');
    final splitHarness = harness.substring(0, harness.indexOf('const hidden')) +
        r'''
const badge = {textContent: '在App打开>', parentElement: null, style: new Style()};
badge.parentElement = {textContent: '在App打开>', parentElement: null, style: new Style()};
const splitText = {nodeType: 3, parentElement: badge};
''' +
        harness.substring(harness.indexOf('global.window')) +
        r'''
global.MutationObserver = class {
  constructor(f) { this.f = f; }
  observe() { this.f([{type: 'childList', addedNodes: [splitText]}]); }
};
''';
    final splitResult = await Process.run(
      'node',
      [
        '-e',
        '$splitHarness$script'
            "if (badge.style.display !== 'none') throw new Error('分离文本未隐藏');",
      ],
    );
    expect(splitResult.exitCode, 0,
        reason: '${splitResult.stdout}${splitResult.stderr}');

    const cacheHarness = r'''
class Style { setProperty(k, v) { this[k] = v; } }
class El {
  constructor(text, position = 'static') {
    this.nodeType = 1; this.style = new Style(); this.position = position;
    this.parentElement = null; this.textContent = text;
  }
}
let styleCalls = 0;
const checkedCard = new El('在App打开', 'fixed');
checkedCard.__pddBadgeChecked = true;
const dynamicTarget = new El('加载中', 'fixed');
dynamicTarget.parentElement = {nodeType: 1, parentElement: null};
const dynamicText = {nodeType: 3, nodeValue: '加载中', parentElement: dynamicTarget};
let observerCb = null;
global.window = {
  getComputedStyle: e => { styleCalls++; return {position: e.position}; },
};
global.document = {
  head: {appendChild() {}},
  createElement: () => new El(''),
  createTreeWalker: () => ({nextNode: () => null}),
  body: new El(''),
};
global.Node = {TEXT_NODE: 3, ELEMENT_NODE: 1};
global.NodeFilter = {SHOW_TEXT: 4};
global.requestAnimationFrame = f => f();
global.MutationObserver = class {
  constructor(f) { observerCb = f; }
  observe() {}
};
''';
    const cacheAssertion = r'''
if (styleCalls !== 0) throw new Error('初始空 body 不应调用 getComputedStyle');
// 已标记 __pddBadgeChecked 的元素节点再次以 childList 新增出现时直接跳过
observerCb([{type: 'childList', addedNodes: [checkedCard]}]);
if (checkedCard.style.display === 'none') throw new Error('已标记元素应跳过检查');
if (styleCalls !== 0) throw new Error('跳过元素不应调用 getComputedStyle');
// 先检查普通文本并打上 __pddBadgeChecked
observerCb([{type: 'childList', addedNodes: [dynamicTarget]}]);
if (!dynamicTarget.__pddBadgeChecked) throw new Error('检查后应打上 __pddBadgeChecked 标记');
// characterData 更新时清除父元素标记并重新检查
dynamicTarget.textContent = '在App打开';
observerCb([{type: 'characterData', target: dynamicText, addedNodes: []}]);
if (dynamicTarget.style.display !== 'none') throw new Error('characterData 更新后应隐藏浮标');
if (styleCalls !== 1) throw new Error('命中浮标时仅应调用 1 次 getComputedStyle，实际 ' + styleCalls);
''';
    final cacheResult = await Process.run(
      'node',
      ['-e', cacheHarness + script + cacheAssertion],
    );
    expect(cacheResult.exitCode, 0,
        reason: '${cacheResult.stdout}${cacheResult.stderr}');
  });
}
