#!/usr/bin/env python3 -I
"""通过 CDP 测量拼多多 H5 的 DOM 清理脚本开销。

不读取或保存凭据；探针会临时读取 innerText 计算开销，不保存页面正文。
依赖 Python websockets（换机需先安装）。
targets 子命令仅用于定位调试目标，会把完整 URL 打到 stdout，可能含订单参数，
不要分享其原始输出；交付数据请用 snapshot/scroll 的脱敏 JSON。

用法：先开启 profile WebView 调试并进入商城，再运行
  python3 -I tools/pdd_web_perf.py snapshot --output <json>
"""
import argparse
import asyncio
import json
import time
import urllib.request

import websockets

PORT = 9222
PROBE = r"""
(async () => {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  let longTaskCount = 0, longTaskTime = 0;
  let observer = null;
  if (window.PerformanceObserver && PerformanceObserver.supportedEntryTypes.includes('longtask')) {
    observer = new PerformanceObserver(list => {
      for (const e of list.getEntries()) { longTaskCount++; longTaskTime += e.duration; }
    });
    observer.observe({type: 'longtask', buffered: false});
  }
  const frames = [];
  let last = performance.now(), running = true;
  function frame(now) { frames.push(now - last); last = now; if (running) requestAnimationFrame(frame); }
  requestAnimationFrame(frame);
  const metrics = [];
  for (let i = 0; i < 10; i++) {
    const nodes = document.querySelectorAll('div, span, a, p, button');
    const start = performance.now();
    for (const el of nodes) {
      const text = (el.innerText || el.textContent || '').trim();
      if (text.length <= 20 && (text.includes('打开App') || text.includes('打开APP') ||
          text.includes('在App打开') || text.includes('App内打开'))) {
        let cur = el;
        for (let d = 0; d < 4 && cur && cur.parentElement; d++) {
          window.getComputedStyle(cur).position;
          cur = cur.parentElement;
        }
      }
    }
    metrics.push({elements: nodes.length, durationMs: performance.now() - start});
    await wait(50);
  }
  await wait(100);
  running = false;
  if (observer) observer.disconnect();
  const sorted = frames.slice(2).sort((a, b) => a - b);
  const pct = p => sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] : null;
  const navigation = performance.getEntriesByType('navigation')[0];
  const images = Array.from(document.images);
  const resources = performance.getEntriesByType('resource').filter(r => r.initiatorType === 'img');
  return {
    capturedAt: new Date().toISOString(),
    urlHost: location.host,
    urlPath: location.pathname,
    titleLength: (document.title || '').length,
    documentElements: document.querySelectorAll('*').length,
    cleanScriptInstalled: !!window.__pddCleanObserver,
    scans: metrics,
    raf: {count: sorted.length, over50ms: sorted.filter(x => x > 50).length,
          p50: pct(.5), p95: pct(.95), p99: pct(.99)},
    longTasks: {count: longTaskCount, totalMs: longTaskTime},
    paint: Object.fromEntries(performance.getEntriesByType('paint').map(x => [x.name, x.startTime])),
    navigation: navigation ? {responseEnd: navigation.responseEnd,
      domContentLoaded: navigation.domContentLoadedEventEnd,
      loadEvent: navigation.loadEventEnd} : null,
    images: {total: images.length,
      failed: images.filter(x => x.complete && x.naturalWidth === 0).length,
      pending: images.filter(x => !x.complete).length,
      lazyNotLoaded: images.filter(x => x.complete && x.naturalWidth === 0 && x.dataset.src).length},
    imageResources: {count: resources.length,
      cacheHits: resources.filter(x => x.transferSize === 0 && x.decodedBodySize > 0).length,
      transferBytes: resources.reduce((sum, x) => sum + x.transferSize, 0),
      decodedBytes: resources.reduce((sum, x) => sum + x.decodedBodySize, 0)}
  };
})()
"""


def targets():
    with urllib.request.urlopen(f'http://localhost:{PORT}/json', timeout=5) as f:
        return json.load(f)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['targets', 'snapshot', 'scroll'])
    parser.add_argument('--output')
    parser.add_argument('--seconds', type=int, default=35)
    args = parser.parse_args()
    pages = [t for t in targets() if t.get('type') == 'page']
    if args.command == 'targets':
        print(json.dumps([{k: t.get(k) for k in ('id', 'type', 'url')} for t in pages], indent=2))
        return
    target = next((t for t in pages if t.get('url', '').rstrip('/') == 'https://mobile.yangkeduo.com'), pages[0])
    async with websockets.connect(target['webSocketDebuggerUrl'], max_size=2**24, ping_interval=None, open_timeout=10) as ws:
        counter = 0
        async def call(method, params=None):
            nonlocal counter
            counter += 1
            await ws.send(json.dumps({'id': counter, 'method': method, 'params': params or {}}))
            while True:
                data = json.loads(await ws.recv())
                if data.get('id') == counter:
                    if 'error' in data: raise RuntimeError(data['error'])
                    return data.get('result', {})
        await call('Page.enable')
        await call('Runtime.enable')
        init = await call('Page.addScriptToEvaluateOnNewDocument', {'source': "window.__pddInitAt=performance.now();window.__pddMallOpenAt=Date.now();"})
        if args.command == 'snapshot':
            result = await call('Runtime.evaluate', {'expression': PROBE, 'awaitPromise': True, 'returnByValue': True})
            data = result['result']['value']
        else:
            await call('Page.removeScriptToEvaluateOnNewDocument', {'identifier': init['identifier']})
            await call('Runtime.evaluate', {'expression': "window.scrollTo({top:0,behavior:'instant'})"})
            await asyncio.sleep(1)
            await call('Runtime.evaluate', {'expression': """
              window.__perfLongTasks = []; window.__perfFrames = [];
              window.__perfObs = new PerformanceObserver(list => window.__perfLongTasks.push(...list.getEntries().map(e => e.duration)));
              window.__perfObs.observe({type:'longtask'}); window.__perfLast = performance.now();
              window.__perfRunning = true;
              window.__perfTick = now => {window.__perfFrames.push(now-window.__perfLast); window.__perfLast=now; if(window.__perfRunning) requestAnimationFrame(window.__perfTick);};
              requestAnimationFrame(window.__perfTick);
            """})
            # 与 adb input 相同的时间序列：35 秒内交替向下/向上滚动。
            for i in range(args.seconds * 2):
                await call('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': 315, 'y': 550 if i % 4 != 3 else 150}]})
                await call('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': 315, 'y': 150 if i % 4 != 3 else 550}]})
                await call('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
                await asyncio.sleep(.5)
            result = await call('Runtime.evaluate', {'expression': """
              (() => {window.__perfRunning=false; window.__perfObs.disconnect();
                const frames=window.__perfFrames.slice(2).sort((a,b)=>a-b); const pct=p=>frames[Math.min(frames.length-1,Math.floor(frames.length*p))]||null;
                const imgs=[...document.images], res=performance.getEntriesByType('resource').filter(x=>x.initiatorType==='img');
                const visible=imgs.filter(x=>{const r=x.getBoundingClientRect();return r.bottom>0&&r.top<innerHeight&&r.width>0&&r.height>0;});
                return {frames:frames.length,over50ms:frames.filter(x=>x>50).length,over100ms:frames.filter(x=>x>100).length,p50:pct(.5),p95:pct(.95),p99:pct(.99),max:frames[frames.length-1],longTaskCount:window.__perfLongTasks.length,longTaskMs:window.__perfLongTasks.reduce((a,b)=>a+b,0),documentElements:document.querySelectorAll('*').length,cleanScriptInstalled:!!window.__pddCleanObserver,images:{total:imgs.length,failed:imgs.filter(x=>x.complete&&x.naturalWidth===0&&!x.dataset.src).length,pending:imgs.filter(x=>!x.complete).length,lazyNotLoaded:imgs.filter(x=>x.complete&&x.naturalWidth===0&&x.dataset.src).length,visibleTotal:visible.length,visibleFailed:visible.filter(x=>x.complete&&x.naturalWidth===0).length,visiblePending:visible.filter(x=>!x.complete).length},imageResources:{count:res.length,cacheHits:res.filter(x=>x.transferSize===0&&x.decodedBodySize>0).length,transferBytes:res.reduce((s,x)=>s+x.transferSize,0),decodedBytes:res.reduce((s,x)=>s+x.decodedBodySize,0)}};})()
            """, 'returnByValue': True})
            data = result['result']['value']
        data['deviceTime'] = time.strftime('%Y-%m-%d %H:%M:%S')
        output = json.dumps(data, ensure_ascii=False, indent=2)
        if args.output:
            with open(args.output, 'w') as f: f.write(output + '\n')
        print(output)

asyncio.run(main())
