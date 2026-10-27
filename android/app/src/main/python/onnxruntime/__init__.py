"""The small part of onnxruntime's Python API that RapidOCR uses, running the models
with Microsoft's onnxruntime for Android (Java, com.logbridge.logbridge.OrtBridge).
onnxruntime has no Python package for Android; the models and their results are the
same, only the engine is called from Java.

Tensors cross to Java as raw float32 bytes (native byte order) plus their shape.
"""

import numpy as np


class GraphOptimizationLevel:
    ORT_DISABLE_ALL = 0
    ORT_ENABLE_BASIC = 1
    ORT_ENABLE_EXTENDED = 2
    ORT_ENABLE_ALL = 99


class SessionOptions:
    """Accepts RapidOCR's settings; the Java side uses full graph optimisation."""
    def __init__(self):
        self.log_severity_level = 2
        self.enable_cpu_mem_arena = True
        self.graph_optimization_level = GraphOptimizationLevel.ORT_ENABLE_ALL
        self.intra_op_num_threads = 0
        self.inter_op_num_threads = 0


def get_available_providers():
    return ["CPUExecutionProvider"]


def get_device():
    return "CPU"


def _java_bridge(model_bytes):
    from java import jclass
    return jclass("com.logbridge.logbridge.OrtBridge").open(model_bytes)


# Replaceable so the same code can be checked on a PC against the real onnxruntime.
open_bridge = _java_bridge


class _Node:
    def __init__(self, name):
        self.name = name


class _ModelMeta:
    def __init__(self, custom):
        self.custom_metadata_map = custom


class InferenceSession:
    def __init__(self, path_or_bytes, sess_options=None, providers=None, **_):
        if isinstance(path_or_bytes, (bytes, bytearray)):
            data = bytes(path_or_bytes)
        else:
            with open(path_or_bytes, "rb") as f:
                data = f.read()
        self._s = open_bridge(data)
        self._inputs = [str(n) for n in self._s.inputNames()]
        self._outputs = [str(n) for n in self._s.outputNames()]

    def get_inputs(self):
        return [_Node(n) for n in self._inputs]

    def get_outputs(self):
        return [_Node(n) for n in self._outputs]

    def get_providers(self):
        return ["CPUExecutionProvider"]

    def get_modelmeta(self):
        keys = [str(k) for k in self._s.metadataKeys()]
        return _ModelMeta({k: str(self._s.metadata(k)) for k in keys})

    def run(self, output_names, input_feed, run_options=None):
        (name, arr), = input_feed.items()
        arr = np.ascontiguousarray(arr, dtype=np.float32)
        res = self._s.run(name, arr.tobytes(), [int(d) for d in arr.shape])
        # [bytes0, shape0, bytes1, shape1, ...] in the model's output order
        outs = {}
        for i, out_name in enumerate(self._outputs):
            data, shape = res[2 * i], res[2 * i + 1]
            outs[out_name] = np.frombuffer(bytes(data), dtype=np.float32).reshape([int(d) for d in shape])
        return [outs[n] for n in (output_names or self._outputs)]
