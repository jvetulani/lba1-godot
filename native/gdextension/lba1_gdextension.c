/* Small C binding for the original simulation. No godot-cpp or SDL runtime. */
#include "gdextension_interface.h"
#include "lba_host.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Holomap flags and current location are owned by the original engine. */
extern unsigned char TabHoloPos[];
extern short NumCube;

typedef union { uint64_t align; unsigned char bytes[64]; } GDValue;
typedef struct { GDExtensionObjectPtr object; } LBAInstance;

static GDExtensionClassLibraryPtr library;
static GDValue class_name, parent_name, empty_name, empty_string;
static GDExtensionInterfaceStringNameNewWithLatin1Chars new_name;
static GDExtensionInterfaceClassdbConstructObject3 construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceStringNewWithUtf8Chars new_string;
static GDExtensionInterfaceStringToUtf8Chars string_utf8;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
static GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor to_type;
static GDExtensionInterfaceVariantConstruct variant_construct;
static GDExtensionInterfaceVariantCall variant_call;
static GDExtensionInterfaceVariantDestroy variant_destroy;
static GDExtensionInterfaceGetVariantGetInternalPtrFunc get_internal;
static GDExtensionInterfacePackedInt32ArrayOperatorIndex packed_int_index;
static GDExtensionVariantGetInternalPtrFunc packed_int_internal;
static GDExtensionVariantFromTypeConstructorFunc from_string, from_int;
static GDExtensionTypeFromVariantConstructorFunc to_string, to_int;

static GDValue resize_name;

static int64_t argument_int(GDExtensionConstVariantPtr arg)
{
    int64_t value = 0;
    to_int(&value, (void *)arg);
    return value;
}

static char *argument_string(GDExtensionConstVariantPtr arg)
{
    GDValue value;
    GDExtensionInt length;
    char *copy;
    to_string(&value, (void *)arg);
    length = string_utf8(&value, NULL, 0);
    copy = malloc((size_t)length + 1);
    if (copy) {
        string_utf8(&value, copy, length);
        copy[length] = 0;
    }
    get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&value);
    return copy;
}

static void return_int(GDExtensionVariantPtr ret, int64_t value)
{ from_int(ret, &value); }

static void return_string(GDExtensionVariantPtr ret, const char *value)
{
    GDValue string;
    new_string(&string, value);
    from_string(ret, &string);
    get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&string);
}

static int32_t *return_packed_ints(GDExtensionVariantPtr ret, int32_t count)
{
    GDValue length, ignored;
    GDExtensionConstVariantPtr args[1];
    GDExtensionCallError error = {0};
    int64_t requested = count;
    variant_construct(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ret, NULL, 0, &error);
    if (error.error != GDEXTENSION_CALL_OK) return NULL;
    from_int(&length, &requested);
    args[0] = &length;
    variant_call(ret, &resize_name, args, 1, &ignored, &error);
    variant_destroy(&ignored);
    variant_destroy(&length);
    return error.error == GDEXTENSION_CALL_OK ? packed_int_internal(ret) : NULL;
}

static void actors_flat(GDExtensionVariantPtr ret)
{
    int i, n = LBA_GetActorCount();
    void *array = return_packed_ints(ret, n * 17);
    for (i = 0; array && i < n; ++i) {
        LBA_ActorSnapshot a;
        int sx = 0, sy = 0, j;
        int32_t fields[17];
        if (!LBA_GetActorSnapshot(i, &a)) continue;
        if ((a.flags & 1024) && a.body >= 0) LBA_GetSpriteOffset(a.body, &sx, &sy);
        fields[0] = a.index; fields[1] = a.x; fields[2] = a.y; fields[3] = a.z;
        fields[4] = a.angle; fields[5] = a.body; fields[6] = a.archive_body;
        fields[7] = a.flags; fields[8] = a.sprite; fields[9] = a.animation;
        fields[10] = a.frame; fields[11] = a.life; fields[12] = sx;
        fields[13] = sy; fields[14] = a.y_max; fields[15] = a.generic_body;
        fields[16] = a.generic_animation;
        for (j = 0; j < 17; ++j) *packed_int_index(array, i * 17 + j) = fields[j];
    }
}

/* Optional visual proxy data. Kept separate from actors_flat() so old
   snapshot readers and the simulation protocol remain unchanged. */
static void collision_flat(GDExtensionVariantPtr ret)
{
    int i, n = LBA_GetActorCount();
    void *array = return_packed_ints(ret, n * 7);
    for (i = 0; array && i < n; ++i) {
        LBA_ActorSnapshot a;
        int32_t fields[7];
        int j;
        if (!LBA_GetActorSnapshot(i, &a)) continue;
        fields[0] = a.index;
        fields[1] = a.collision_xmin;
        fields[2] = a.collision_xmax;
        fields[3] = a.collision_ymin;
        fields[4] = a.collision_ymax;
        fields[5] = a.collision_zmin;
        fields[6] = a.collision_zmax;
        for (j = 0; j < 7; ++j) *packed_int_index(array, i * 7 + j) = fields[j];
    }
}

static void poses_flat(GDExtensionVariantPtr ret)
{
    /* One authoritative native interpolation pass per visible BODY actor.
       Group counts are normally small; the bound mirrors the host ABI. */
    static int32_t fields[200 * (2 + 200 * 4)];
    int32_t groups[200 * 4];
    int used = 0, i, j, count;
    void *array;
    for (i = 0; i < LBA_GetActorCount() && i < 200; ++i) {
        count = LBA_GetActorPose(i, groups, 200 * 4);
        if (count <= 0) continue;
        fields[used++] = i;
        fields[used++] = count;
        memcpy(fields + used, groups, (size_t)count * 4 * sizeof(int32_t));
        used += count * 4;
    }
    array = return_packed_ints(ret, used);
    for (j = 0; array && j < used; ++j)
        *packed_int_index(array, j) = fields[j];
}

static void extras_flat(GDExtensionVariantPtr ret)
{
    int i, j, n = 0;
    void *array;
    LBA_ExtraSnapshot e;
    for (i = 0; i < LBA_GetExtraCount(); ++i) if (LBA_GetExtraSnapshot(i, &e)) ++n;
    array = return_packed_ints(ret, n * 10);
    n = 0;
    for (i = 0; array && i < LBA_GetExtraCount(); ++i) {
        int sx = 0, sy = 0;
        int32_t fields[10];
        if (!LBA_GetExtraSnapshot(i, &e)) continue;
        if ((e.sprite & 0x8000) == 0) LBA_GetSpriteOffset(e.sprite, &sx, &sy);
        fields[0] = e.index; fields[1] = e.x; fields[2] = e.y; fields[3] = e.z;
        fields[4] = e.sprite; fields[5] = e.flags; fields[6] = e.age_ticks;
        fields[7] = e.quantity; fields[8] = sx; fields[9] = sy;
        for (j = 0; j < 10; ++j) *packed_int_index(array, n * 10 + j) = fields[j];
        ++n;
    }
}

static void events_flat(GDExtensionVariantPtr ret)
{
    LBA_Event e;
    int32_t fields[14 * 128];
    int n = 0, j;
    void *array;
    /* A single tick should not normally exceed 128 events. Retain the rest
       in the native FIFO for the next host poll, instead of silently dropping. */
    while (n < 128 && LBA_PollEvent(&e)) {
        int32_t *f = fields + n * 14;
        f[0] = e.type; f[1] = e.scene; f[2] = e.previous_scene;
        f[3] = e.island; f[4] = e.actor_count; f[5] = e.resource;
        f[6] = e.x; f[7] = e.y; f[8] = e.z; f[9] = e.left;
        f[10] = e.right; f[11] = e.pitch; f[12] = e.repeat; f[13] = e.flags;
        ++n;
    }
    array = return_packed_ints(ret, n * 14);
    for (j = 0; array && j < n * 14; ++j) *packed_int_index(array, j) = fields[j];
}

static void dialogue_fields(GDExtensionVariantPtr ret)
{
    LBA_DialogueRequest d;
    int j;
    void *array;
    if (!LBA_GetDialogueRequest(&d)) { return_packed_ints(ret, 0); return; }
    array = return_packed_ints(ret, 7);
    if (!array) return;
    {
        int32_t fields[7] = {(int32_t)d.serial, d.text_id, d.bank, d.speaker,
                             d.voice_index, d.large_window, LBA_GetDialogueSpeakerColour()};
        for (j = 0; j < 7; ++j) *packed_int_index(array, j) = fields[j];
    }
}

static void status_flat(GDExtensionVariantPtr ret)
{
    LBA_GameplayStatus s;
    int32_t fields[8], i;
    void *array;
    if (!LBA_GetGameplayStatus(&s)) { return_packed_ints(ret, 0); return; }
    fields[0] = s.behavior; fields[1] = s.health;
    fields[2] = s.magic_level; fields[3] = s.magic_energy;
    fields[4] = s.clovers; fields[5] = s.clover_boxes;
    fields[6] = s.keys; fields[7] = s.money;
    array = return_packed_ints(ret, 8);
    for (i = 0; array && i < 8; ++i) *packed_int_index(array, i) = fields[i];
}

static void camera_flat(GDExtensionVariantPtr ret)
{
    int32_t fields[5], i, n = LBA_GetCameraState(fields, 5);
    void *array = return_packed_ints(ret, n);
    for (i = 0; array && i < n; ++i)
        *packed_int_index(array, i) = fields[i];
}

static void inventory_flat(GDExtensionVariantPtr ret)
{
    int32_t fields[28], i, n = LBA_GetInventoryFlags(fields, 28);
    void *array = return_packed_ints(ret, n);
    for (i = 0; array && i < n; ++i) *packed_int_index(array, i) = fields[i];
}

static void holomap_flat(GDExtensionVariantPtr ret)
{
    int32_t *array = return_packed_ints(ret, 151);
    int i;
    if (!array) return;
    *packed_int_index(array, 0) = NumCube;
    for (i = 0; i < 150; ++i)
        *packed_int_index(array, i + 1) = TabHoloPos[i];
}

enum { M_START, M_STEP, M_ACTORS, M_POSES, M_EXTRAS, M_EVENTS,
       M_DIALOGUE_FIELDS, M_DIALOGUE_TEXT, M_STATUS, M_SCENE, M_TICK,
       M_ACK, M_BEHAVIOR, M_HAS_SLOT, M_SAVE_SLOT, M_LOAD_SLOT,
       M_SHUTDOWN, M_ABI, M_GRID_OVERLAY, M_GRID_OVERLAY_CEILING,
       M_INVENTORY, M_CAMERA, M_COLLISION, M_SET_WALL_DAMAGE, M_GET_WALL_DAMAGE, M_HOLOMAP };

static void method_call(void *user, GDExtensionClassInstancePtr instance,
                        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
                        GDExtensionVariantPtr ret, GDExtensionCallError *error)
{
    intptr_t method = (intptr_t)user;
    int64_t result = 0;
    (void)instance;
    error->error = GDEXTENSION_CALL_OK;
    if (count != ((method == M_START || method == M_STEP || method == M_ACK ||
                   method == M_BEHAVIOR || method == M_HAS_SLOT ||
                   method == M_SAVE_SLOT || method == M_LOAD_SLOT ||
                   method == M_SET_WALL_DAMAGE) ? 1 : 0)) {
        error->error = count < 1 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        return;
    }
    switch (method) {
    case M_START: {
        char *path = argument_string(args[0]);
        result = path && LBA_SimulationInitialize(path) && LBA_SimulationNewGame();
        free(path);
        break;
    }
    case M_STEP:
        LBA_SetGameplayActions((uint32_t)argument_int(args[0]));
        result = LBA_SimulationStep();
        break;
    case M_ACTORS: actors_flat(ret); return;
    case M_COLLISION: collision_flat(ret); return;
    case M_SET_WALL_DAMAGE: {
        LBA_AudioSettings settings;
        if (!LBA_GetAudioSettings(&settings)) { result = 0; break; }
        settings.wall_collision_damage = argument_int(args[0]) != 0;
        result = LBA_SetAudioSettings(&settings);
        break;
    }
    case M_GET_WALL_DAMAGE: {
        LBA_AudioSettings settings;
        result = LBA_GetAudioSettings(&settings) ? settings.wall_collision_damage : -1;
        break;
    }
    case M_POSES: poses_flat(ret); return;
    case M_EXTRAS: extras_flat(ret); return;
    case M_EVENTS: events_flat(ret); return;
    case M_DIALOGUE_FIELDS: dialogue_fields(ret); return;
    case M_STATUS: status_flat(ret); return;
    case M_INVENTORY: inventory_flat(ret); return;
    case M_HOLOMAP: holomap_flat(ret); return;
    case M_CAMERA: camera_flat(ret); return;
    case M_DIALOGUE_TEXT: {
        LBA_DialogueRequest d;
        return_string(ret, LBA_GetDialogueRequest(&d) ? d.text_utf8 : "");
        return;
    }
    case M_SCENE: result = LBA_GetSceneNumber(); break;
    case M_GRID_OVERLAY: result = LBA_GetGridOverlay(); break;
    case M_GRID_OVERLAY_CEILING: result = LBA_GetGridOverlayCeiling(); break;
    case M_TICK: result = LBA_GetTick(); break;
    case M_ACK: result = LBA_AcknowledgeDialogue((uint32_t)argument_int(args[0])); break;
    case M_BEHAVIOR: result = LBA_SetBehavior((int32_t)argument_int(args[0])); break;
    case M_HAS_SLOT: result = LBA_SimulationHasSlot((int32_t)argument_int(args[0])); break;
    case M_SAVE_SLOT: result = LBA_SimulationSaveSlot((int32_t)argument_int(args[0])); break;
    case M_LOAD_SLOT: result = LBA_SimulationLoadSlot((int32_t)argument_int(args[0])); break;
    case M_SHUTDOWN: LBA_SimulationShutdown(); result = 1; break;
    case M_ABI: result = LBA_GetHostABIVersion(); break;
    }
    return_int(ret, result);
}

static GDExtensionObjectPtr create_instance(void *user, GDExtensionBool notify)
{
    LBAInstance *instance = calloc(1, sizeof(*instance));
    (void)user; (void)notify;
    if (!instance) return NULL;
    instance->object = construct_object(&parent_name);
    if (!instance->object) { free(instance); return NULL; }
    set_instance(instance->object, &class_name, instance);
    return instance->object;
}

static void free_instance(void *user, GDExtensionClassInstancePtr instance)
{ (void)user; free(instance); }

static void bind_method(const char *name, int id, GDExtensionVariantType result_type,
                        GDExtensionVariantType arg_type)
{
    GDValue method_name, arg_name, return_name;
    GDExtensionClassMethodInfo info = {0};
    GDExtensionPropertyInfo result = {0}, argument = {0};
    GDExtensionClassMethodArgumentMetadata metadata = 0;
    new_name(&method_name, name, 0);
    new_name(&return_name, "return", 0);
    info.name = &method_name;
    info.method_userdata = (void *)(intptr_t)id;
    info.call_func = method_call;
    info.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    info.has_return_value = 1;
    result.type = result_type;
    result.name = &return_name;
    result.class_name = &empty_name;
    result.hint_string = &empty_string;
    result.usage = 6;
    info.return_value_info = &result;
    if (arg_type != GDEXTENSION_VARIANT_TYPE_NIL) {
        new_name(&arg_name, "value", 0);
        argument.type = arg_type;
        argument.name = &arg_name;
        argument.class_name = &empty_name;
        argument.hint_string = &empty_string;
        argument.usage = 6;
        info.argument_count = 1;
        info.arguments_info = &argument;
        info.arguments_metadata = &metadata;
    }
    register_method(library, &class_name, &info);
    /* Method metadata is copied by ClassDB. StringName's small allocation
       remains live until extension unload; this also supports editor reload. */
}

static void initialize(void *user, GDExtensionInitializationLevel level)
{
    GDExtensionClassCreationInfo6 info = {0};
    (void)user;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    new_name(&class_name, "LBASimulation", 0);
    new_name(&parent_name, "Object", 0);
    new_name(&empty_name, "", 0);
    new_string(&empty_string, "");
    new_name(&resize_name, "resize", 0);
    info.is_exposed = 1;
    info.create_instance_func = create_instance;
    info.free_instance_func = free_instance;
    register_class(library, &class_name, &parent_name, &info);
    bind_method("start", M_START, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_STRING);
    bind_method("step", M_STEP, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("actors_flat", M_ACTORS, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("collision_flat", M_COLLISION, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("set_wall_damage", M_SET_WALL_DAMAGE, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("get_wall_damage", M_GET_WALL_DAMAGE, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("poses_flat", M_POSES, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("extras_flat", M_EXTRAS, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("events_flat", M_EVENTS, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("dialogue_fields", M_DIALOGUE_FIELDS, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("dialogue_text", M_DIALOGUE_TEXT, GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("status_flat", M_STATUS, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("inventory_flat", M_INVENTORY, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("holomap_flat", M_HOLOMAP, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("camera_flat", M_CAMERA, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("scene_number", M_SCENE, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("grid_overlay", M_GRID_OVERLAY, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("grid_overlay_ceiling", M_GRID_OVERLAY_CEILING, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("tick", M_TICK, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("acknowledge_dialogue", M_ACK, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("set_behavior", M_BEHAVIOR, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("has_slot", M_HAS_SLOT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("save_slot", M_SAVE_SLOT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("load_slot", M_LOAD_SLOT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("shutdown", M_SHUTDOWN, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("abi_version", M_ABI, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL);
}

static void deinitialize(void *user, GDExtensionInitializationLevel level)
{
    (void)user;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    LBA_SimulationShutdown();
    unregister_class(library, &class_name);
}

GDExtensionBool lba1_gdextension_init(GDExtensionInterfaceGetProcAddress get,
                                     GDExtensionClassLibraryPtr lib,
                                     GDExtensionInitialization *initialization)
{
#define LOAD(field, type, name) field = (type)get(name); if (!field) return 0
    library = lib;
    LOAD(new_name, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
    LOAD(construct_object, GDExtensionInterfaceClassdbConstructObject3, "classdb_construct_object3");
    LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
    LOAD(new_string, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
    LOAD(string_utf8, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
    LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
    LOAD(variant_construct, GDExtensionInterfaceVariantConstruct, "variant_construct");
    LOAD(variant_call, GDExtensionInterfaceVariantCall, "variant_call");
    LOAD(variant_destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD(get_internal, GDExtensionInterfaceGetVariantGetInternalPtrFunc, "variant_get_ptr_internal_getter");
    LOAD(packed_int_index, GDExtensionInterfacePackedInt32ArrayOperatorIndex, "packed_int32_array_operator_index");
#undef LOAD
    from_string = from_type(GDEXTENSION_VARIANT_TYPE_STRING);
    from_int = from_type(GDEXTENSION_VARIANT_TYPE_INT);
    to_string = to_type(GDEXTENSION_VARIANT_TYPE_STRING);
    to_int = to_type(GDEXTENSION_VARIANT_TYPE_INT);
    packed_int_internal = get_internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    if (!from_string || !from_int || !to_string || !to_int || !packed_int_internal) return 0;
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->userdata = NULL;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    return 1;
}
