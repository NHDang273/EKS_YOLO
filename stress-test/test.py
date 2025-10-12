#!/usr/bin/env python3
"""
Simple stress test for YOLO API - test auto-scaling
"""
import requests
import time
import random
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse

def send_request(api_url, image_path, request_id):
    """Send one request"""
    try:
        start = time.time()
        with open(image_path, 'rb') as f:
            files = {'file': f}
            resp = requests.post(f"{api_url}/predict", files=files, timeout=60)
        elapsed = time.time() - start

        if resp.status_code == 200:
            data = resp.json()
            return {
                'success': True,
                'time': elapsed,
                'detections': len(data.get('detections', [])),
                'pod': data.get('pod_name', 'unknown')
            }
        return {'success': False, 'error': f"HTTP {resp.status_code}"}
    except Exception as e:
        return {'success': False, 'error': str(e)}

def run_test(api_url, image_dir, concurrent, total, duration):
    """Run stress test"""
    # Get all images
    images = list(Path(image_dir).glob('*.jpg')) + \
             list(Path(image_dir).glob('*.jpeg')) + \
             list(Path(image_dir).glob('*.png'))

    if not images:
        print(f"❌ No images found in {image_dir}")
        return

    print(f"📸 Found {len(images)} images")
    print(f"🎯 API: {api_url}")
    print(f"⚡ Concurrent: {concurrent}, Total: {total}")

    # Test health
    try:
        resp = requests.get(f"{api_url}/health", timeout=5)
        print(f"✅ Health check: {resp.json()}\n")
    except:
        print("⚠️  Cannot reach API\n")
        return

    # Run test
    results = []
    start_time = time.time()

    with ThreadPoolExecutor(max_workers=concurrent) as executor:
        futures = []
        request_count = 0

        while True:
            # Check if we should stop
            if duration and (time.time() - start_time) >= duration:
                break
            if total and request_count >= total:
                break

            # Submit requests
            while len(futures) < concurrent:
                if total and request_count >= total:
                    break
                if duration and (time.time() - start_time) >= duration:
                    break

                img = random.choice(images)
                future = executor.submit(send_request, api_url, str(img), request_count)
                futures.append(future)
                request_count += 1

            # Check completed
            done = [f for f in futures if f.done()]
            for f in done:
                results.append(f.result())
                futures.remove(f)

                if len(results) % 10 == 0:
                    success = sum(1 for r in results if r.get('success'))
                    print(f"Progress: {len(results)} requests ({success} success)")

            time.sleep(0.1)

        # Wait for remaining
        for f in futures:
            results.append(f.result())

    # Print stats
    elapsed = time.time() - start_time
    success_results = [r for r in results if r.get('success')]
    failed = len(results) - len(success_results)

    print(f"\n{'='*50}")
    print(f"📊 RESULTS")
    print(f"{'='*50}")
    print(f"Total time: {elapsed:.1f}s")
    print(f"Total requests: {len(results)}")
    print(f"✅ Success: {len(success_results)} ({len(success_results)/len(results)*100:.1f}%)")
    print(f"❌ Failed: {failed}")
    print(f"Throughput: {len(results)/elapsed:.1f} req/s")

    if success_results:
        times = [r['time'] for r in success_results]
        print(f"\n⏱️  Response times:")
        print(f"  Min: {min(times):.2f}s")
        print(f"  Max: {max(times):.2f}s")
        print(f"  Avg: {sum(times)/len(times):.2f}s")

        # Pod distribution
        pods = {}
        for r in success_results:
            pod = r.get('pod', 'unknown')
            pods[pod] = pods.get(pod, 0) + 1

        print(f"\n🎯 Pod distribution:")
        for pod, count in sorted(pods.items()):
            print(f"  {pod}: {count} ({count/len(success_results)*100:.1f}%)")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Simple YOLO stress test')
    parser.add_argument('--url', help='API URL (or use kubectl to get LoadBalancer)')
    parser.add_argument('--images', default='test-images', help='Image directory (default: test-images)')
    parser.add_argument('--concurrent', type=int, default=5, help='Concurrent requests (default: 5)')
    parser.add_argument('--total', type=int, help='Total requests (leave empty for duration-based)')
    parser.add_argument('--duration', type=int, help='Test duration in seconds')

    args = parser.parse_args()

    # Get LoadBalancer URL if not provided
    if not args.url:
        print("🔍 Getting LoadBalancer URL from kubectl...")
        import subprocess
        try:
            result = subprocess.run(
                ['kubectl', 'get', 'svc', 'yolo-service', '-n', 'yolo-inference',
                 '-o', 'jsonpath={.status.loadBalancer.ingress[0].hostname}'],
                capture_output=True, text=True, check=True
            )
            hostname = result.stdout.strip()
            if not hostname:
                result = subprocess.run(
                    ['kubectl', 'get', 'svc', 'yolo-service', '-n', 'yolo-inference',
                     '-o', 'jsonpath={.status.loadBalancer.ingress[0].ip}'],
                    capture_output=True, text=True, check=True
                )
                hostname = result.stdout.strip()

            if hostname:
                args.url = f"http://{hostname}"
                print(f"✅ Found: {args.url}\n")
            else:
                print("❌ Cannot get LoadBalancer address")
                exit(1)
        except Exception as e:
            print(f"❌ Error getting LoadBalancer: {e}")
            print("Please provide --url manually")
            exit(1)

    # Default: 50 requests or 5 minutes
    if not args.total and not args.duration:
        args.total = 50

    run_test(args.url, args.images, args.concurrent, args.total, args.duration)
