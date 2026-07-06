import fs from 'fs';
import potrace from 'potrace';
import svg2vd from 'svg2vectordrawable';

const inputPath = 'C:\\Users\\Huri_\\Documents\\proyectos\\repertoriobc\\public\\assets\\icono.png';
const xmlPath = 'C:\\Users\\Huri_\\Documents\\proyectos\\repertorio_bc\\android\\app\\src\\main\\res\\drawable\\ic_notification.xml';

potrace.trace(inputPath, async function(err, svg) {
    if (err) {
        console.error("Error tracing:", err);
        return;
    }
    
    // El SVG generado no tiene currentColor, lo añadimos para que sea dinámico
    let modifiedSvg = svg;
    
    console.log("SVG generated. Converting to VectorDrawable...");
    const xmlCode = await svg2vd(modifiedSvg);
    
    // Inyectamos el fillColor en el XML para que coincida con el tema
    const finalXml = xmlCode.replace('<path', '<path\n        android:fillColor="@color/splash_icon"');
    
    fs.writeFileSync(xmlPath, finalXml);
    console.log("Done! Saved as VectorDrawable XML.");
});
