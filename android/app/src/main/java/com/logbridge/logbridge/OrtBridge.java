package com.logbridge.logbridge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

/**
 * One ONNX model run with Microsoft's onnxruntime for Android, for the embedded Python
 * (python/onnxruntime/__init__.py): RapidOCR's text detection, direction and recognition
 * models, the same ones DSR Extract uses on the PC. Tensors are float32, passed as raw
 * bytes in native byte order plus their shape.
 */
public final class OrtBridge {
    private static final OrtEnvironment ENV = OrtEnvironment.getEnvironment();
    private final OrtSession session;
    private final List<String> outputs;

    private OrtBridge(OrtSession session) {
        this.session = session;
        this.outputs = new ArrayList<>(session.getOutputNames());
    }

    public static OrtBridge open(byte[] model) throws OrtException {
        OrtSession.SessionOptions o = new OrtSession.SessionOptions();
        o.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT);
        o.setIntraOpNumThreads(Math.max(1, Math.min(4, Runtime.getRuntime().availableProcessors())));
        return new OrtBridge(ENV.createSession(model, o));
    }

    public String[] inputNames() {
        return session.getInputNames().toArray(new String[0]);
    }

    public String[] outputNames() {
        return outputs.toArray(new String[0]);
    }

    public String[] metadataKeys() throws OrtException {
        return session.getMetadata().getCustomMetadata().keySet().toArray(new String[0]);
    }

    public String metadata(String key) throws OrtException {
        return session.getMetadata().getCustomMetadata().get(key);
    }

    /** -> [bytes0, shape0, bytes1, shape1, ...] in output order. */
    public Object[] run(String input, byte[] data, long[] shape) throws OrtException {
        FloatBuffer in = ByteBuffer.wrap(data).order(ByteOrder.nativeOrder()).asFloatBuffer();
        Object[] out = new Object[outputs.size() * 2];
        try (OnnxTensor tensor = OnnxTensor.createTensor(ENV, in, shape);
             OrtSession.Result result = session.run(Collections.singletonMap(input, tensor))) {
            for (int i = 0; i < outputs.size(); i++) {
                OnnxTensor t = (OnnxTensor) result.get(i);
                FloatBuffer f = t.getFloatBuffer();
                ByteBuffer b = ByteBuffer.allocate(f.remaining() * 4).order(ByteOrder.nativeOrder());
                b.asFloatBuffer().put(f);
                out[2 * i] = b.array();
                out[2 * i + 1] = t.getInfo().getShape();
            }
        }
        return out;
    }
}
