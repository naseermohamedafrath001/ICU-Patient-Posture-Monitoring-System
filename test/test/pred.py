import argparse, os, json
from pathlib import Path
import torch
import torch.nn as nn
import torchvision.transforms as T
from torchvision import models
from PIL import Image
import numpy as np

def load_checkpoint(weights_path):
    ckpt = torch.load(weights_path, map_location="cpu")
    # We saved: {"state_dict": ..., "classes": [...], "img_size": 224}
    classes = ckpt.get("classes", None)
    img_size = int(ckpt.get("img_size", 224))
    state_dict = ckpt["state_dict"]
    return state_dict, classes, img_size

def build_model(num_classes):
    model = models.resnet18(weights=None)
    model.fc = nn.Linear(model.fc.in_features, num_classes)
    model.eval()
    return model

def get_eval_transform(img_size):
    return T.Compose([
        T.Grayscale(num_output_channels=3),
        T.Resize(256),
        T.CenterCrop(img_size),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225]),
    ])

def predict_one(model, transform, img_path, class_names):
    img = Image.open(img_path).convert("L")
    x = transform(img).unsqueeze(0)
    with torch.no_grad():
        logits = model(x)
        probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
    idx = int(np.argmax(probs))
    return class_names[idx], float(probs[idx]), probs

def is_image(p):
    return p.suffix.lower() in {".png",".jpg",".jpeg",".bmp",".tif",".tiff"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", required=True, help="Path to best .pth")
    ap.add_argument("--image", help="Path to a single image")
    ap.add_argument("--folder", help="Folder with images (optionally in class subfolders)")
    ap.add_argument("--save_json", help="Optional: save predictions to this JSON file")
    args = ap.parse_args()

    state_dict, classes, img_size = load_checkpoint(args.weights)
    if classes is None:
        raise ValueError("Checkpoint does not contain 'classes'. Re-train/save with classes or set CLASS_NAMES manually.")

    # Build and load model
    model = build_model(len(classes))
    model.load_state_dict(state_dict)
    model.eval()
    transform = get_eval_transform(img_size)

    results = []

    if args.image:
        label, conf, probs = predict_one(model, transform, args.image, classes)
        print(f"[{Path(args.image).name}] -> {label} ({conf:.3f})")
        print("probs:", {c: float(probs[i]) for i, c in enumerate(classes)})
        results.append({"file": args.image, "pred": label, "conf": conf,
                        "probs": {c: float(probs[i]) for i,c in enumerate(classes)}})

    if args.folder:
        folder = Path(args.folder)
        files = [p for p in folder.rglob("*") if p.is_file() and is_image(p)]
        correct = total = 0
        for p in files:
            pred, conf, probs = predict_one(model, transform, str(p), classes)
            # If folder has class subdirs, we can auto-derive GT
            gt = None
            for c in classes:
                if f"/{c}/" in str(p.as_posix()) or p.parent.name.lower()==c.lower():
                    gt = c; break
            ok = (gt is not None and pred == gt)
            total += 1
            correct += int(ok) if gt is not None else 0
            print(f"{p.name:30} pred={pred:7} conf={conf:.3f}  gt={gt or '-'}  {'✓' if ok else ' '}")
            results.append({"file": str(p), "pred": pred, "conf": conf, "gt": gt,
                            "probs": {c: float(probs[i]) for i,c in enumerate(classes)}})
        if total > 0 and any(r.get("gt") for r in results):
            denom = sum(1 for r in results if r.get("gt"))
            acc = correct / max(denom,1)
            print(f"\nFolder accuracy (only files with GT from folder name): {acc*100:.2f}%")

    if args.save_json:
        with open(args.save_json, "w") as f:
            json.dump({"classes": classes, "preds": results}, f, indent=2)
        print("Saved predictions:", args.save_json)

if __name__ == "__main__":
    main()
