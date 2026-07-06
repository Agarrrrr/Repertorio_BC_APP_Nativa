from PIL import Image
import os

try:
    img_path = 'C:/Users/Huri_/Documents/proyectos/repertorio_bc/assets/icono.png'
    if not os.path.exists(img_path):
        print("File not found")
        exit(1)
        
    img = Image.open(img_path).convert('RGBA')
    datas = img.getdata()
    
    new_data_light = []
    new_data_dark = []
    
    for item in datas:
        r, g, b, a = item
        
        # Calculate luminance (0 to 255)
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        
        # Invert luminance to get alpha (dark pixels = opaque, light pixels = transparent)
        new_alpha = int((255 - luminance) * (a / 255.0))
        
        # Dark mode theme: White logo
        new_data_dark.append((255, 255, 255, new_alpha))
        # Light mode theme: Dark blue logo (#001F54)
        new_data_light.append((0, 31, 84, new_alpha))
            
    img_dark = Image.new('RGBA', img.size)
    img_dark.putdata(new_data_dark)
    img_dark.save('assets/splash_icon_dark.png')
    
    img_light = Image.new('RGBA', img.size)
    img_light.putdata(new_data_light)
    img_light.save('assets/splash_icon_light.png')
    
    print("Success smoothing")
except Exception as e:
    print("Error", e)
