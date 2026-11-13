// Pruebas de firestore.rules. Correr con:
// firebase emulators:exec --only firestore "npm --prefix test/rules test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
} from 'firebase/firestore';

/** Fecha "AAAA-MM-DD" a `dias` de hoy (UTC, igual que timestamp.date en las reglas). */
function fecha(dias) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

const HACE_5 = fecha(-5);

let env;

/** Contexto con sesión; por defecto correo verificado. */
const como = (uid, email = `${uid}@ejemplo.com`, verificado = true) =>
  env.authenticatedContext(uid, { email, email_verified: verificado }).firestore();

const pase = (claseId, grupoId, profesorUid, f) => ({
  claseId,
  grupoId,
  profesorUid,
  materia: 'Matemáticas',
  salon: 'A1',
  fecha: f,
  marcadoEn: serverTimestamp(),
  estados: { 1: 0, 2: 1, 3: 0 },
});

setLogLevel('silent'); // los PERMISSION_DENIED esperados ensucian la salida

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-paselista',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const usuario = (rol) => ({ nombre: rol, email: `${rol}@ejemplo.com`, fotoUrl: null, rol });
    await setDoc(doc(db, 'usuarios/admin'), usuario('admin'));
    await setDoc(doc(db, 'usuarios/profe'), usuario('profesor'));
    await setDoc(doc(db, 'usuarios/profe2'), usuario('profesor'));
    await setDoc(doc(db, 'usuarios/orden'), usuario('orden'));
    await setDoc(doc(db, 'invitaciones/nuevo@ejemplo.com'), { rol: 'profesor', creadoPor: 'admin' });
    await setDoc(doc(db, 'invitaciones/otro@ejemplo.com'), { rol: 'orden', creadoPor: 'admin' });
    await setDoc(doc(db, 'grupos/g1'), { nombre: '1A', profesores: ['profe'], alumnos: [] });
    await setDoc(doc(db, 'grupos/g2'), { nombre: '1B', profesores: ['profe2'], alumnos: [] });
    await setDoc(doc(db, 'clases/profe_g1'), { profesorUid: 'profe', grupoId: 'g1', materia: 'Matemáticas', salon: 'A1' });
    await setDoc(doc(db, 'clases/profe2_g2'), { profesorUid: 'profe2', grupoId: 'g2', materia: 'Historia', salon: 'B2' });
    await setDoc(doc(db, `pases/profe_g1_${HACE_5}`), pase('profe_g1', 'g1', 'profe', HACE_5));
    await setDoc(doc(db, `pases/profe2_g2_${HACE_5}`), pase('profe2_g2', 'g2', 'profe2', HACE_5));
  });
});

describe('invitaciones', () => {
  test('el admin lista y escribe', async () => {
    const db = como('admin');
    await assertSucceeds(getDocs(collection(db, 'invitaciones')));
    await assertSucceeds(setDoc(doc(db, 'invitaciones/x@ejemplo.com'), { rol: 'orden', creadoPor: 'admin' }));
  });

  test('el profe no lista ni escribe', async () => {
    const db = como('profe');
    await assertFails(getDocs(collection(db, 'invitaciones')));
    await assertFails(setDoc(doc(db, 'invitaciones/x@ejemplo.com'), { rol: 'admin', creadoPor: 'profe' }));
  });

  test('un usuario lee la suya aunque el token traiga mayúsculas, pero no la de otro', async () => {
    const db = como('nuevo', 'Nuevo@Ejemplo.COM');
    await assertSucceeds(getDoc(doc(db, 'invitaciones/nuevo@ejemplo.com')));
    await assertFails(getDoc(doc(db, 'invitaciones/otro@ejemplo.com')));
  });
});

describe('alta de usuario', () => {
  const alta = (cambios = {}) => ({
    nombre: 'Profe Nuevo',
    email: 'nuevo@ejemplo.com',
    fotoUrl: null,
    rol: 'profesor',
    ...cambios,
  });

  test('funciona con el rol invitado', async () => {
    await assertSucceeds(setDoc(doc(como('nuevo', 'Nuevo@Ejemplo.com'), 'usuarios/nuevo'), alta()));
  });

  test('acepta fotoUrl como string', async () => {
    await assertSucceeds(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ fotoUrl: 'https://ejemplo.com/f.png' })));
  });

  test('se rechaza con otro rol', async () => {
    await assertFails(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ rol: 'admin' })));
  });

  test('se rechaza con otro uid', async () => {
    await assertFails(setDoc(doc(como('nuevo'), 'usuarios/otro'), alta()));
  });

  test('se rechaza con el correo sin verificar', async () => {
    await assertFails(setDoc(doc(como('nuevo', 'nuevo@ejemplo.com', false), 'usuarios/nuevo'), alta()));
  });

  test('se rechaza con campos extra', async () => {
    await assertFails(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ extra: true })));
  });

  test('se rechaza con un email distinto al del token', async () => {
    await assertFails(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ email: 'otro@ejemplo.com' })));
  });

  test('se rechaza con nombre vacío, de más de 100 o que no es string', async () => {
    const db = como('nuevo');
    await assertFails(setDoc(doc(db, 'usuarios/nuevo'), alta({ nombre: '' })));
    await assertFails(setDoc(doc(db, 'usuarios/nuevo'), alta({ nombre: 'a'.repeat(101) })));
    await assertFails(setDoc(doc(db, 'usuarios/nuevo'), alta({ nombre: 7 })));
    await assertSucceeds(setDoc(doc(db, 'usuarios/nuevo'), alta({ nombre: 'a'.repeat(100) })));
  });

  test('acepta un nombre de 100 caracteres con acentos (size() cuenta caracteres, no bytes)', async () => {
    await assertSucceeds(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ nombre: 'é'.repeat(100) })));
  });

  test('se rechaza con fotoUrl que no es string ni null', async () => {
    await assertFails(setDoc(doc(como('nuevo'), 'usuarios/nuevo'), alta({ fotoUrl: 5 })));
  });
});

describe('usuarios', () => {
  test('cada quien lee solo el suyo', async () => {
    const db = como('profe');
    await assertSucceeds(getDoc(doc(db, 'usuarios/profe')));
    await assertFails(getDoc(doc(db, 'usuarios/admin')));
    await assertFails(getDocs(collection(db, 'usuarios')));
  });

  test('el admin lee todos y puede borrar', async () => {
    const db = como('admin');
    await assertSucceeds(getDocs(collection(db, 'usuarios')));
    await assertSucceeds(deleteDoc(doc(db, 'usuarios/profe2')));
  });
});

describe('grupos y clases', () => {
  test('el profe solo lee sus grupos', async () => {
    const db = como('profe');
    await assertSucceeds(getDoc(doc(db, 'grupos/g1')));
    await assertFails(getDoc(doc(db, 'grupos/g2')));
    await assertSucceeds(getDocs(query(collection(db, 'grupos'), where('profesores', 'array-contains', 'profe'))));
    await assertFails(getDocs(collection(db, 'grupos')));
  });

  test('el profe solo lee sus clases', async () => {
    const db = como('profe');
    await assertSucceeds(getDoc(doc(db, 'clases/profe_g1')));
    await assertFails(getDoc(doc(db, 'clases/profe2_g2')));
    await assertSucceeds(getDocs(query(collection(db, 'clases'), where('profesorUid', '==', 'profe'))));
    await assertFails(getDocs(collection(db, 'clases')));
  });

  test('orden lee todo pero no escribe', async () => {
    const db = como('orden');
    await assertSucceeds(getDocs(collection(db, 'grupos')));
    await assertSucceeds(getDocs(collection(db, 'clases')));
    await assertSucceeds(getDocs(collection(db, 'pases')));
    await assertFails(setDoc(doc(db, 'grupos/g3'), { nombre: '1C', profesores: [], alumnos: [] }));
    await assertFails(setDoc(doc(db, 'clases/orden_g1'), { profesorUid: 'orden', grupoId: 'g1' }));
    await assertFails(updateDoc(doc(db, `pases/profe_g1_${HACE_5}`), { 'estados.1': 1 }));
  });
});

describe('pases', () => {
  const crear = (f) =>
    setDoc(doc(como('profe'), `pases/profe_g1_${f}`), pase('profe_g1', 'g1', 'profe', f));

  test('el profe crea un pase de hoy y uno de hace 27 días', async () => {
    await assertSucceeds(crear(fecha(0)));
    await assertSucceeds(crear(fecha(-27)));
  });

  test('se rechaza un pase con el grupoId de otro grupo', async () => {
    const f = fecha(0);
    await assertFails(setDoc(doc(como('profe'), `pases/profe_g1_${f}`), pase('profe_g1', 'g2', 'profe', f)));
  });

  test('se rechaza un pase cuyo ID no es {claseId}_{fecha}', async () => {
    const db = como('profe');
    const f = fecha(0);
    await assertFails(setDoc(doc(db, `pases/profe_g1_${fecha(-1)}`), pase('profe_g1', 'g1', 'profe', f)));
    await assertFails(setDoc(doc(db, 'pases/x7Kq2'), pase('profe_g1', 'g1', 'profe', f)));
  });

  test('se rechaza un pase sobre la clase de otro profe aunque ponga su propio profesorUid', async () => {
    const f = fecha(0);
    await assertFails(setDoc(doc(como('profe'), `pases/profe2_g2_${f}`), pase('profe2_g2', 'g2', 'profe', f)));
  });

  test('se rechazan uno de hace 30 días y uno de mañana', async () => {
    await assertFails(crear(fecha(-30)));
    await assertFails(crear(fecha(1)));
  });

  test('al editar solo puede cambiar estados y marcas de tiempo', async () => {
    const ref = doc(como('profe'), `pases/profe_g1_${HACE_5}`);
    await assertSucceeds(updateDoc(ref, { 'estados.3': 2, editadoEn: serverTimestamp() }));
    await assertFails(updateDoc(ref, { salon: 'B2' }));
    await assertFails(updateDoc(ref, { fecha: fecha(-1) }));
    await assertFails(updateDoc(ref, { profesorUid: 'profe2' }));
    await assertFails(updateDoc(ref, { grupoId: 'g2' }));
    await assertFails(updateDoc(ref, { claseId: 'profe2_g2' }));
  });

  test('no edita pases de otro profe', async () => {
    const ref = doc(como('profe'), `pases/profe2_g2_${HACE_5}`);
    await assertFails(updateDoc(ref, { 'estados.1': 1, editadoEn: serverTimestamp() }));
  });
});
