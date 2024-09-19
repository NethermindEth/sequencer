use std::collections::HashMap;

use ark_ff::BigInt;
use cairo_lang_sierra::ids::FunctionId;
use cairo_lang_starknet_classes::contract_class::ContractEntryPoint;
use cairo_native::execution_result::ContractExecutionResult;
use cairo_native::executor::AotNativeExecutor;
use cairo_native::starknet::{ResourceBounds, SyscallResult, TxV2Info, U256};
use cairo_vm::vm::runners::cairo_runner::ExecutionResources;
use itertools::Itertools;
use num_bigint::BigUint;
use num_traits::ToBytes;
use starknet_api::core::{ContractAddress, EntryPointSelector};
use starknet_api::transaction::{AllResourceBounds, ValidResourceBounds};
use starknet_types_core::felt::Felt;

use crate::execution::call_info::{CallExecution, CallInfo, Retdata};
use crate::execution::entry_point::{CallEntryPoint, EntryPointExecutionResult};
use crate::execution::errors::EntryPointExecutionError;
use crate::execution::native::syscall_handler::NativeSyscallHandler;
use crate::execution::syscalls::hint_processor::{L1_DATA_GAS, L1_GAS, L2_GAS};
use crate::transaction::objects::CurrentTransactionInfo;

#[cfg(test)]
#[path = "utils_test.rs"]
pub mod test;

pub fn contract_address_to_native_felt(contract_address: ContractAddress) -> Felt {
    *contract_address.0.key()
}

pub fn contract_entrypoint_to_entrypoint_selector(
    entrypoint: &ContractEntryPoint,
) -> EntryPointSelector {
    let selector_felt = Felt::from_bytes_be_slice(&entrypoint.selector.to_be_bytes());
    EntryPointSelector(selector_felt)
}

pub fn run_native_executor(
    native_executor: &AotNativeExecutor,
    function_id: &FunctionId,
    call: CallEntryPoint,
    mut syscall_handler: NativeSyscallHandler<'_>,
) -> EntryPointExecutionResult<CallInfo> {
    let execution_result = native_executor.invoke_contract_dynamic(
        function_id,
        &call.calldata.0,
        Some(call.initial_gas.into()),
        &mut syscall_handler,
    );

    let run_result = match execution_result {
        Ok(res) if res.failure_flag => Err(EntryPointExecutionError::NativeExecutionError {
            info: if !res.return_values.is_empty() {
                decode_felts_as_str(&res.return_values)
            } else {
                String::from("Unknown error")
            },
        }),
        Err(runner_err) => {
            Err(EntryPointExecutionError::NativeUnexpectedError { source: runner_err })
        }
        Ok(res) => Ok(res),
    }?;

    create_callinfo(call, run_result, syscall_handler)
}

fn create_callinfo(
    call: CallEntryPoint,
    run_result: ContractExecutionResult,
    syscall_handler: NativeSyscallHandler<'_>,
) -> Result<CallInfo, EntryPointExecutionError> {
    let gas_consumed = {
        // We can use `.unwrap()` directly in both cases because the most significant bit is could
        // be only 63 here (128 = 64 + 64).
        let low: u64 = (run_result.remaining_gas & ((1u128 << 64) - 1)).try_into().unwrap();
        let high: u64 = (run_result.remaining_gas >> 64).try_into().unwrap();
        if high != 0 {
            return Err(EntryPointExecutionError::NativeExecutionError {
                info: "Overflow: gas consumed bigger than 64 bit".into(),
            });
        }
        call.initial_gas - low
    };

    Ok(CallInfo {
        call,
        execution: CallExecution {
            retdata: Retdata(run_result.return_values),
            events: syscall_handler.events,
            l2_to_l1_messages: syscall_handler.l2_to_l1_messages,
            failed: run_result.failure_flag,
            gas_consumed,
        },
        resources: ExecutionResources {
            n_steps: 0,
            n_memory_holes: 0,
            builtin_instance_counter: HashMap::default(),
        },
        inner_calls: syscall_handler.inner_calls,
        storage_read_values: syscall_handler.storage_read_values,
        accessed_storage_keys: syscall_handler.accessed_storage_keys,
    })
}

pub fn u256_to_biguint(u256: U256) -> BigUint {
    let lo = BigUint::from(u256.lo);
    let hi = BigUint::from(u256.hi);

    (hi << 128) + lo
}

pub fn big4int_to_u256(b_int: BigInt<4>) -> U256 {
    let [a, b, c, d] = b_int.0;

    let lo = u128::from(a) | (u128::from(b) << 64);
    let hi = u128::from(c) | (u128::from(d) << 64);

    U256 { lo, hi }
}

pub fn encode_str_as_felts(msg: &str) -> Vec<Felt> {
    const CHUNK_SIZE: usize = 32;

    let data = msg.as_bytes().chunks(CHUNK_SIZE - 1);
    let mut encoding = vec![Felt::default(); data.len()];
    for (i, data_chunk) in data.enumerate() {
        let mut chunk = [0_u8; CHUNK_SIZE];
        chunk[1..data_chunk.len() + 1].copy_from_slice(data_chunk);
        encoding[i] = Felt::from_bytes_be(&chunk);
    }
    encoding
}

pub fn decode_felts_as_str(encoding: &[Felt]) -> String {
    let bytes_err: Vec<_> =
        encoding.iter().flat_map(|felt| felt.to_bytes_be()[1..32].to_vec()).collect();

    match String::from_utf8(bytes_err) {
        Ok(s) => s.trim_matches('\0').to_owned(),
        Err(_) => {
            let err_msgs = encoding
                .iter()
                .map(|felt| match String::from_utf8(felt.to_bytes_be()[1..32].to_vec()) {
                    Ok(s) => format!("{} ({})", s.trim_matches('\0'), felt),
                    Err(_) => felt.to_string(),
                })
                .join(", ");
            format!("[{}]", err_msgs)
        }
    }
}

pub fn default_tx_v2_info() -> TxV2Info {
    TxV2Info {
        version: Default::default(),
        account_contract_address: Default::default(),
        max_fee: 0,
        signature: vec![],
        transaction_hash: Default::default(),
        chain_id: Default::default(),
        nonce: Default::default(),
        resource_bounds: vec![],
        tip: 0,
        paymaster_data: vec![],
        nonce_data_availability_mode: 0,
        fee_data_availability_mode: 0,
        account_deployment_data: vec![],
    }
}

pub fn calculate_resource_bounds(
    tx_info: &CurrentTransactionInfo,
) -> SyscallResult<Vec<ResourceBounds>> {
    let l1_gas_felt = Felt::from_hex(L1_GAS).map_err(|e| encode_str_as_felts(&e.to_string()))?;
    let l2_gas_felt = Felt::from_hex(L2_GAS).map_err(|e| encode_str_as_felts(&e.to_string()))?;
    // TODO: Recheck correctness of L1_DATA_GAS
    let l1_data_gas_felt =
        Felt::from_hex(L1_DATA_GAS).map_err(|e| encode_str_as_felts(&e.to_string()))?;

    let mut resource_bounds = vec![
        ResourceBounds{
            resource: l1_gas_felt,
            max_amount: tx_info.resource_bounds.get_l1_bounds().max_amount,
            max_price_per_unit: tx_info.resource_bounds.get_l1_bounds().max_price_per_unit,
        },
        ResourceBounds{
            resource: l2_gas_felt,
            max_amount: tx_info.resource_bounds.get_l2_bounds().max_amount,
            max_price_per_unit: tx_info.resource_bounds.get_l2_bounds().max_price_per_unit,
        },
    ];

    if let ValidResourceBounds::AllResources(AllResourceBounds { l1_data_gas, .. }) =
        tx_info.resource_bounds
    {
        resource_bounds.push(ResourceBounds{
            resource: l1_data_gas_felt,
            max_amount: l1_data_gas.max_amount,
            max_price_per_unit: l1_data_gas.max_price_per_unit,
        });
    }

    Ok(resource_bounds)
}
