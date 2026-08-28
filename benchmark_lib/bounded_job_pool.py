import threading
from concurrent.futures import ThreadPoolExecutor

class BoundedJobPool:
    def __init__(self, maximum_concurrent_jobs):
        self.maximum_concurrent_jobs = maximum_concurrent_jobs
        self._slot = threading.Semaphore(maximum_concurrent_jobs)

    def run_one(self, function, *arguments):
        with self._slot:
            return function(*arguments)

    def map_over(self, function, items, worker_count=None):
        workers = worker_count or self.maximum_concurrent_jobs
        with ThreadPoolExecutor(max_workers=workers) as executor:
            return list(executor.map(
                lambda item: self.run_one(function, item), items))
