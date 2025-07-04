#!/bin/bash

# === Configurable Parameters ===
INPUT_VIDEO="input.mp4"
HEF_PATH="yolov5m_vehicles.hef"
POSTPROCESS_LIB="/home/ridgerun/hailo-rpi5-examples/venv_hailo_rpi5_examples/lib/python3.11/site-packages/resources/libyolo_hailortpp_postprocess.so"
POSTPROCESS_CONFIG="yolov5_vehicle_detection.json"
CROPPER_SO="/usr/lib/aarch64-linux-gnu/hailo/tappas/post_processes/cropping_algorithms/libwhole_buffer.so"

QUEUE_OPTS="leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0"
QUEUE_BYPASS_OPTS="leaky=no max-size-buffers=20 max-size-bytes=0 max-size-time=0"

BATCH_SIZE=2
VDEVICE_ID=1
NMS_SCORE=0.3
NMS_IOU=0.45
HAILO_OUTPUT_FORMAT="HAILO_FORMAT_TYPE_FLOAT32"
INFERENCE_FUNCTION="filter_letterbox"

# === Subpipelines ===

INPUT_PIPELINE="
  filesrc location=${INPUT_VIDEO} !
  queue ${QUEUE_OPTS} !
  decodebin !
  queue ${QUEUE_OPTS} !
  videoscale n-threads=2 !
  queue ${QUEUE_OPTS} !
  videoconvert n-threads=3 qos=false !
  video/x-raw, pixel-aspect-ratio=1/1, format=RGB, width=1280, height=720 !
  queue ${QUEUE_OPTS}
"

# Generate crops from full frame to feed into model
CROPPER_PIPELINE="
  hailocropper name=inference_wrapper_crop \
    so-path=${CROPPER_SO} \
    function-name=create_crops \
    use-letterbox=true \
    resize-method=inter-area \
    internal-offset=true
"

# Merge original frames and inference results
AGGREGATOR_PIPELINE="
  hailoaggregator name=inference_wrapper_agg
  inference_wrapper_crop. ! queue ${QUEUE_BYPASS_OPTS} ! inference_wrapper_agg.sink_0
"

# Crop stream into inference branch
INFERENCE_BRANCH="
  inference_wrapper_crop. ! queue ${QUEUE_OPTS} !
  videoscale n-threads=2 qos=false !
  queue ${QUEUE_OPTS} !
  video/x-raw, pixel-aspect-ratio=1/1 !
  videoconvert n-threads=2 !
  queue ${QUEUE_OPTS} !
  hailonet name=inference_hailonet \
    hef-path=${HEF_PATH} \
    batch-size=${BATCH_SIZE} \
    vdevice-group-id=${VDEVICE_ID} \
    nms-score-threshold=${NMS_SCORE} \
    nms-iou-threshold=${NMS_IOU} \
    output-format-type=${HAILO_OUTPUT_FORMAT} \
    force-writable=true !
  queue ${QUEUE_OPTS} !
  hailofilter name=inference_hailofilter \
    so-path=${POSTPROCESS_LIB} \
    function-name=${INFERENCE_FUNCTION} \
    config-path=${POSTPROCESS_CONFIG} \
    qos=false !
  queue ${QUEUE_OPTS} !
  inference_wrapper_agg.sink_1
"

# Post-inference: tracking and rendering
POST_PIPELINE="
  inference_wrapper_agg. ! queue ${QUEUE_OPTS} !
  hailotracker name=hailo_tracker \
    class-id=1 \
    kalman-dist-thr=0.8 \
    iou-thr=0.9 \
    init-iou-thr=0.7 \
    keep-new-frames=2 \
    keep-tracked-frames=2 \
    keep-lost-frames=2 \
    keep-past-metadata=false \
    qos=false !
  queue ${QUEUE_OPTS} !
  identity name=identity_callback !
  queue ${QUEUE_OPTS} !
  hailooverlay name=hailo_display_overlay !
  queue ${QUEUE_OPTS} !
  videoconvert n-threads=2 qos=false !
  queue ${QUEUE_OPTS} !
  fpsdisplaysink name=hailo_display \
    video-sink=autovideosink \
    sync=false \
    text-overlay=false \
    signal-fps-measurements=true
"

# === Execute full pipeline ===
gst-launch-1.0 -e \
  ${INPUT_PIPELINE} ! \
  ${CROPPER_PIPELINE} \
  ${AGGREGATOR_PIPELINE} \
  ${INFERENCE_BRANCH} \
  ${POST_PIPELINE}
