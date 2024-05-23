from brownie.network import Chain
import time

chain = Chain()

def get_batch_base():
    return {
        "version": "1.0",
        "chainId": str(chain.id),
        "createdAt": str(int(time.time() * 1000)),
        "meta": {
            "name": "Transactions Batch",
            "description": "",
            "txBuilderVersion": "1.16.1"
        },
        "transactions": []
    }

def append_txn(batchBase, txn):
    batchBase['transactions'].append({
        "to": txn.receiver,
        "value": str(txn.value),
        "data": txn.input,
        "contractMethod": { "inputs": [], "name": "fallback", "payable": True },
        "contractInputsValues": None
    })