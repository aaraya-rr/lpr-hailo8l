#!/bin/bash

INPUT_VIDEO="input.mp4"
HEF_PATH="yolov5m_vehicles.hef"
POSTPROCESS_LIB="/home/ridgerun/hailo-rpi5-examples/venv_hailo_rpi5_examples/lib/python3.11/site-packages/resources/libyolo_hailortpp_postprocess.so"
POSTPROCESS_CONFIG="yolov5_vehicle_detection.json"

QUEUE_OPTS="leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0"

gst-launch-1.0 -e \
  filesrc location="${INPUT_VIDEO}" name=source ! \
  queue name=source_queue_decode ${QUEUE_OPTS} ! \
  decodebin name=source_decodebin ! \
  queue name=source_scale_q ${QUEUE_OPTS} ! \
  videoscale name=source_videoscale n-threads=2 ! \
  queue name=source_convert_q ${QUEUE_OPTS} ! \
  videoconvert name=source_convert n-threads=3 qos=false ! \
  video/x-raw, pixel-aspect-ratio=1/1, format=RGB, width=1280, height=720 ! \
  queue name=inference_scale_q ${QUEUE_OPTS} ! \
  videoscale name=inference_videoscale n-threads=2 qos=false ! \
  queue name=inference_convert_q ${QUEUE_OPTS} ! \
  video/x-raw, pixel-aspect-ratio=1/1 ! \
  videoconvert name=inference_videoconvert n-threads=2 ! \
  queue name=inference_hailonet_q ${QUEUE_OPTS} ! \
  hailonet name=inference_hailonet \
    hef-path="${HEF_PATH}" \
    batch-size=1 \
    vdevice-group-id=1 \
    nms-score-threshold=0.3 \
    nms-iou-threshold=0.45 \
    output-format-type=HAILO_FORMAT_TYPE_FLOAT32 \
    force-writable=true ! \
  queue name=inference_hailofilter_q ${QUEUE_OPTS} ! \
  hailofilter name=inference_hailofilter \
    so-path="${POSTPROCESS_LIB}" \
    function-name=filter \
    config-path="${POSTPROCESS_CONFIG}" \
    qos=false ! \
  queue name=inference_output_q ${QUEUE_OPTS} ! \
  queue name=identity_callback_q ${QUEUE_OPTS} ! \
  identity name=identity_callback ! \
  queue name=hailo_display_overlay_q ${QUEUE_OPTS} ! \
  hailooverlay name=hailo_display_overlay ! \
  queue name=hailo_display_videoconvert_q ${QUEUE_OPTS} ! \
  videoconvert name=hailo_display_videoconvert n-threads=2 qos=false ! \
  queue name=hailo_display_q ${QUEUE_OPTS} ! \
  videoconvert ! openh264enc ! mpegtsmux ! filesink location=output.ts
